**FREE
// ===========================================================================
//  MPUTIL - buffers, CCSID conversion, base64, SHA-1, random numbers,
//           PEM decoding, IFS file reading and error signalling.
// ===========================================================================
ctl-opt nomain ccsid(*char:*jobrun) alloc(*teraspace)
        option(*srcstmt:*nodebugio) bnddir('QC2LE');

/copy mpint.rpgleinc

// ---------------------------------------------------------------------------
//  iconv
// ---------------------------------------------------------------------------
dcl-ds QtqCode_t qualified template inz;
  ccsid    int(10) inz(0);
  convAlt  int(10) inz(0);
  substAlt int(10) inz(0);
  shiftAlt int(10) inz(0);
  inpLenOp int(10) inz(0);
  errorOpt int(10) inz(0);
  reserved char(8) inz(*allx'00');
end-ds;

dcl-ds iconv_t qualified template inz;
  rtn int(10);
  cd  int(10) dim(12);
end-ds;

dcl-pr QtqIconvOpen likeds(iconv_t) extproc('QtqIconvOpen');
  toCode   likeds(QtqCode_t);
  fromCode likeds(QtqCode_t);
end-pr;

dcl-pr iconv uns(10) extproc('iconv');
  cd      likeds(iconv_t) value;
  inBuf   pointer;
  inLeft  uns(10);
  outBuf  pointer;
  outLeft uns(10);
end-pr;

dcl-ds toUtf8   likeds(iconv_t);
dcl-s  convReady ind inz(*off);

// ---------------------------------------------------------------------------
//  System APIs
// ---------------------------------------------------------------------------
dcl-ds ApiError_t qualified template inz;
  bytesProv  int(10) inz(%size(ApiError_t));
  bytesAvail int(10) inz(0);
  msgId      char(7);
  reserved   char(1);
  msgData    char(512);
end-ds;

dcl-pr QC3CALHA extpgm('QC3CALHA');
  inData     char(1) options(*varsize);
  inLen      int(10) const;
  inFormat   char(8) const;
  algDesc    int(10) const;
  algFormat  char(8) const;
  provider   char(1) const;
  device     char(10) const;
  hash       char(64);
  err        likeds(ApiError_t);
end-pr;

dcl-pr QC3GENRN extpgm('QC3GENRN');
  prnData    char(1) options(*varsize);
  prnLen     int(10) const;
  prnType    char(1) const;
  prnParity  char(1) const;
  err        likeds(ApiError_t);
end-pr;

dcl-pr QMHSNDPM extpgm('QMHSNDPM');
  msgId      char(7) const;
  msgFile    char(20) const;
  msgData    char(4096) const options(*varsize);
  msgDataLen int(10) const;
  msgType    char(10) const;
  stackEntry char(10) const;
  stackCount int(10) const;
  msgKey     char(4);
  err        likeds(ApiError_t);
end-pr;

// ---------------------------------------------------------------------------
//  IFS / errno
// ---------------------------------------------------------------------------
dcl-pr c_open int(10) extproc('open');
  path  pointer value options(*string);
  oflag int(10) value;
end-pr;

dcl-pr c_read int(10) extproc('read');
  fd  int(10) value;
  buf pointer value;
  len uns(10) value;
end-pr;

dcl-pr c_close int(10) extproc('close');
  fd int(10) value;
end-pr;

dcl-pr errno_p pointer extproc('__errno');
end-pr;

dcl-pr strerror pointer extproc('strerror');
  errnum int(10) value;
end-pr;

dcl-c O_RDONLY 1;

// ---------------------------------------------------------------------------
//  Error state
// ---------------------------------------------------------------------------
dcl-ds lastError likeds(MP_ServerResponse_t) inz;

// base64 tables
dcl-ds b64 qualified;
  ready ind inz(*off);
  // the alphabet, as UTF-8 (= ASCII) bytes
  alpha varchar(64) ccsid(*utf8)
        inz('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/');
  // ASCII code -> 6 bit value (-1 = not part of the alphabet)
  value int(5) dim(256);
end-ds;

// ===========================================================================
//  Buffers
// ===========================================================================
dcl-proc mp_buf_reserve export;
  dcl-pi *n;
    buf   likeds(mp_Buffer_t);
    extra int(10) value;
  end-pi;
  dcl-s need   int(20);
  dcl-s newCap int(20);

  need = buf.len + extra;
  if need <= buf.cap and buf.data <> *null;
    return;
  endif;
  newCap = buf.cap;
  if newCap < 1024;
    newCap = 1024;
  endif;
  dow newCap < need;
    newCap *= 2;
  enddo;
  if newCap > 2147483647;
    mp_throw('Mapepire: buffer size limit exceeded');
  endif;
  if buf.data = *null;
    buf.data = %alloc(newCap);
    buf.len = 0;
  else;
    buf.data = %realloc(buf.data : newCap);
  endif;
  buf.cap = newCap;
end-proc;

dcl-proc mp_buf_addBytes export;
  dcl-pi *n;
    buf likeds(mp_Buffer_t);
    ptr pointer value;
    len int(10) value;
  end-pi;
  if len <= 0;
    return;
  endif;
  mp_buf_reserve(buf : len);
  mp_memcpy(buf.data + buf.len : ptr : len);
  buf.len += len;
end-proc;

dcl-proc mp_buf_addByte export;
  dcl-pi *n;
    buf  likeds(mp_Buffer_t);
    byte uns(3) value;
  end-pi;
  dcl-s p pointer;
  dcl-s b uns(3) based(p);
  mp_buf_reserve(buf : 1);
  p = buf.data + buf.len;
  b = byte;
  buf.len += 1;
end-proc;

dcl-proc mp_buf_addText export;
  dcl-pi *n;
    buf  likeds(mp_Buffer_t);
    text varchar(MP_SQL_MAX:4) const;
  end-pi;
  // a CONST parameter's address cannot be taken - work on a copy
  dcl-s copy varchar(MP_SQL_MAX:4) static;
  copy = text;
  mp_buf_addNative(buf : %addr(copy:*data) : %len(copy));
end-proc;

dcl-proc mp_buf_addNative export;
  dcl-pi *n;
    buf likeds(mp_Buffer_t);
    ptr pointer value;
    len int(10) value;
  end-pi;
  dcl-s inP     pointer;
  dcl-s inLeft  uns(10);
  dcl-s outP    pointer;
  dcl-s outLeft uns(10);
  dcl-s room    int(10);
  dcl-s rc      uns(10);

  if len <= 0;
    return;
  endif;
  initConv();
  // worst case: 3 UTF-8 bytes per EBCDIC byte (+ shift state slack)
  room = len * 3 + 16;
  mp_buf_reserve(buf : room);
  inP = ptr;
  inLeft = len;
  outP = buf.data + buf.len;
  outLeft = room;
  rc = iconv(toUtf8 : inP : inLeft : outP : outLeft);
  buf.len += room - outLeft;
end-proc;

dcl-proc mp_buf_free export;
  dcl-pi *n;
    buf likeds(mp_Buffer_t);
  end-pi;
  if buf.data <> *null;
    dealloc buf.data;
  endif;
  buf.data = *null;
  buf.len = 0;
  buf.cap = 0;
end-proc;

dcl-proc mp_utf8ToText export;
  dcl-pi *n varchar(MP_VALUE_MAX:4);
    ptr pointer value;
    len int(10) value;
  end-pi;
  // RPG converts CCSID(*UTF8) to the job CCSID on assignment. (iconv
  // cannot be used for this direction: QtqIconvOpen does not accept the
  // "job CCSID" value 0 as the target.)
  dcl-c WORK_MAX 262140;
  dcl-s work varchar(WORK_MAX:4) ccsid(*utf8) static;
  dcl-s n    int(10);

  if len <= 0 or ptr = *null;
    return '';
  endif;
  n = len;
  if n > WORK_MAX;
    n = WORK_MAX;
  endif;
  %len(work) = n;
  mp_memcpy(%addr(work:*data) : ptr : n);
  return work;
end-proc;

dcl-proc initConv;
  dcl-ds utf8   likeds(QtqCode_t) inz(*likeds);
  dcl-ds native likeds(QtqCode_t) inz(*likeds);
  if convReady;
    return;
  endif;
  utf8.ccsid = 1208;
  // 0 = the job's (default) CCSID
  native.ccsid = 0;
  toUtf8 = QtqIconvOpen(utf8 : native);
  if toUtf8.rtn < 0;
    mp_throw('Mapepire: unable to open CCSID conversion to/from UTF-8');
  endif;
  convReady = *on;
end-proc;

// ===========================================================================
//  base64
// ===========================================================================

dcl-proc initBase64;
  dcl-s i int(10);
  dcl-s p pointer;
  dcl-s c uns(3) based(p);
  if b64.ready;
    return;
  endif;
  b64.value(*) = -1;
  for i = 0 to 63;
    p = %addr(b64.alpha:*data) + i;
    b64.value(c + 1) = i;
  endfor;
  b64.ready = *on;
end-proc;

dcl-proc mp_base64Encode export;
  dcl-pi *n;
    ptr pointer value;
    len int(10) value;
    outBuf likeds(mp_Buffer_t);
  end-pi;
  dcl-s i    int(10);
  dcl-s b0   int(10);
  dcl-s b1   int(10);
  dcl-s b2   int(10);
  dcl-s rem  int(10);
  dcl-s pIn  pointer;
  dcl-s byte uns(3) based(pIn);
  dcl-s pA   pointer;
  dcl-s abyt uns(3) based(pA);
  dcl-s quad uns(3) dim(4);
  dcl-s k    int(10);

  initBase64();
  mp_buf_reserve(outBuf : (len + 2) / 3 * 4 + 4);
  i = 0;
  dow i < len;
    rem = len - i;
    pIn = ptr + i;
    b0 = byte;
    b1 = 0;
    b2 = 0;
    if rem > 1;
      pIn = ptr + i + 1;
      b1 = byte;
    endif;
    if rem > 2;
      pIn = ptr + i + 2;
      b2 = byte;
    endif;
    pA = %addr(b64.alpha:*data) + %div(b0:4);
    quad(1) = abyt;
    pA = %addr(b64.alpha:*data) + %rem(b0:4) * 16 + %div(b1:16);
    quad(2) = abyt;
    pA = %addr(b64.alpha:*data) + %rem(b1:16) * 4 + %div(b2:64);
    quad(3) = abyt;
    pA = %addr(b64.alpha:*data) + %rem(b2:64);
    quad(4) = abyt;
    if rem = 1;
      quad(3) = 61;
      quad(4) = 61;
    elseif rem = 2;
      quad(4) = 61;
    endif;
    for k = 1 to 4;
      mp_buf_addByte(outBuf : quad(k));
    endfor;
    i += 3;
  enddo;
end-proc;

dcl-proc mp_base64Decode export;
  dcl-pi *n ind;
    ptr pointer value;
    len int(10) value;
    outBuf likeds(mp_Buffer_t);
  end-pi;
  dcl-s i     int(10);
  dcl-s pIn   pointer;
  dcl-s c     uns(3) based(pIn);
  dcl-s v     int(10);
  dcl-s acc   int(10) inz(0);
  dcl-s bits  int(10) inz(0);
  dcl-s divisor int(10);
  dcl-s k     int(10);

  initBase64();
  for i = 0 to len - 1;
    pIn = ptr + i;
    // whitespace
    if c = 32 or c = 9 or c = 10 or c = 13;
      iter;
    endif;
    // padding ends the data
    if c = 61;
      leave;
    endif;
    v = b64.value(c + 1);
    if v < 0;
      return *off;
    endif;
    acc = %rem(acc * 64 + v : 16777216);
    bits += 6;
    if bits >= 8;
      bits -= 8;
      divisor = 1;
      for k = 1 to bits;
        divisor *= 2;
      endfor;
      mp_buf_addByte(outBuf : %rem(%div(acc : divisor) : 256));
    endif;
  endfor;
  return *on;
end-proc;

// ===========================================================================
//  SHA-1 and random bytes (Cryptographic Services APIs)
// ===========================================================================
dcl-proc mp_sha1 export;
  dcl-pi *n char(20);
    ptr pointer value;
    len int(10) value;
  end-pi;
  dcl-ds err likeds(ApiError_t) inz(*likeds);
  dcl-s hash char(64);
  dcl-s data char(1) based(ptr);

  // algorithm 2 = SHA-1, provider 0 = any
  QC3CALHA(data : len : 'DATA0100' : 2 : 'ALGD0500' : '0' : *blanks
           : hash : err);
  if err.bytesAvail > 0;
    mp_throw('Mapepire: SHA-1 calculation failed: ' + err.msgId);
  endif;
  return %subst(hash : 1 : 20);
end-proc;

dcl-proc mp_random export;
  dcl-pi *n;
    ptr pointer value;
    len int(10) value;
  end-pi;
  dcl-ds err likeds(ApiError_t) inz(*likeds);
  dcl-s data char(1) based(ptr);
  QC3GENRN(data : len : '0' : '0' : err);
  if err.bytesAvail > 0;
    mp_throw('Mapepire: random number generation failed: ' + err.msgId);
  endif;
end-proc;

// ===========================================================================
//  PEM -> DER (first certificate in the text)
// ===========================================================================
dcl-proc mp_pemToDer export;
  dcl-pi *n ind;
    ptr pointer value;
    len int(10) value;
    der likeds(mp_Buffer_t);
  end-pi;
  dcl-s text   varchar(MP_VALUE_MAX:4);
  dcl-s begTag varchar(40) inz('-----BEGIN CERTIFICATE-----');
  dcl-s endTag varchar(40) inz('-----END CERTIFICATE-----');
  dcl-s b      int(10);
  dcl-s e      int(10);
  dcl-ds body  likeds(mp_Buffer_t) inz;

  // PEM is plain ASCII; look at it in the job CCSID to find the markers
  text = mp_utf8ToText(ptr : len);
  b = %scan(begTag : text);
  if b = 0;
    return *off;
  endif;
  b += %len(begTag);
  e = %scan(endTag : text : b);
  if e = 0;
    return *off;
  endif;
  mp_buf_addText(body : %subst(text : b : e - b));
  der.len = 0;
  if not mp_base64Decode(body.data : body.len : der);
    mp_buf_free(body);
    return *off;
  endif;
  mp_buf_free(body);
  return der.len > 0;
end-proc;

// ===========================================================================
//  IFS
// ===========================================================================
dcl-proc mp_readFile export;
  dcl-pi *n;
    path varchar(1024) const;
    outBuf  likeds(mp_Buffer_t);
  end-pi;
  dcl-s fd int(10);
  dcl-s n  int(10);

  fd = c_open(%trim(path) : O_RDONLY);
  if fd < 0;
    mp_throw('Mapepire: cannot open ' + %trim(path) + ': ' + mp_errnoText());
  endif;
  dou n <= 0;
    mp_buf_reserve(outBuf : 65536);
    n = c_read(fd : outBuf.data + outBuf.len : 65536);
    if n > 0;
      outBuf.len += n;
    endif;
  enddo;
  c_close(fd);
  if n < 0;
    mp_throw('Mapepire: cannot read ' + %trim(path) + ': ' + mp_errnoText());
  endif;
end-proc;

dcl-proc mp_errnoText export;
  dcl-pi *n varchar(256);
  end-pi;
  dcl-s pErr pointer;
  dcl-s err  int(10) based(pErr);
  pErr = errno_p();
  return %str(strerror(err)) + ' (errno ' + %char(err) + ')';
end-proc;

// ===========================================================================
//  Errors
// ===========================================================================
dcl-proc mp_setLastError export;
  dcl-pi *n;
    resp likeds(MP_ServerResponse_t) const;
  end-pi;
  lastError = resp;
end-proc;

dcl-proc MP_getLastError export;
  dcl-pi *n likeds(MP_ServerResponse_t);
  end-pi;
  return lastError;
end-proc;

dcl-proc mp_throw export;
  dcl-pi *n;
    text varchar(4096) const;
  end-pi;
  clear lastError;
  lastError.success = *off;
  lastError.error = text;
  sendEscape(text);
end-proc;

dcl-proc mp_throwResponse export;
  dcl-pi *n;
    resp   likeds(MP_ServerResponse_t) const;
    prefix varchar(256) const options(*nopass);
  end-pi;
  dcl-s text varchar(4096);
  lastError = resp;
  text = resp.error;
  if %parms >= %parmnum(prefix);
    text = prefix + text;
  endif;
  if resp.sqlState <> '';
    text += ' (SQLSTATE ' + resp.sqlState + ', SQLCODE '
          + %char(resp.sqlRc) + ')';
  endif;
  sendEscape(text);
end-proc;

dcl-proc mp_rethrow export;
  if lastError.error = '';
    lastError.error = 'Mapepire: unexpected error';
  endif;
  sendEscape(lastError.error);
end-proc;

// Send CPF9898 *ESCAPE two entries up: to the caller of whoever called
// mp_throw / mp_throwResponse / mp_rethrow. Being unhandled there, it
// percolates up to the application, so internal MONITOR groups can still
// clean up on the way.
dcl-proc sendEscape;
  dcl-pi *n;
    text varchar(4096) const;
  end-pi;
  dcl-ds err likeds(ApiError_t) inz(*likeds);
  dcl-s key  char(4);
  dcl-s data varchar(512);
  data = text;
  QMHSNDPM('CPF9898' : 'QCPFMSG   *LIBL' : data : %len(data)
           : '*ESCAPE' : '*' : 2 : key : err);
end-proc;

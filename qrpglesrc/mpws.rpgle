**FREE
// ===========================================================================
//  MPWS - minimal WebSocket client (RFC 6455) on top of MPTRANS
//
//  - HTTP/1.1 upgrade handshake with Basic authentication and verification
//    of Sec-WebSocket-Accept
//  - masked client frames (text, ping/pong, close)
//  - reassembly of fragmented messages, 16/64 bit payload lengths
// ===========================================================================
ctl-opt nomain ccsid(*char:*jobrun) alloc(*teraspace)
        option(*srcstmt:*nodebugio) bnddir('QC2LE');

/copy mpint.rpgleinc

dcl-c OP_CONT  0;
dcl-c OP_TEXT  1;
dcl-c OP_BIN   2;
dcl-c OP_CLOSE 8;
dcl-c OP_PING  9;
dcl-c OP_PONG  10;

dcl-c WS_GUID '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
dcl-c READ_CHUNK 65536;

// ===========================================================================
dcl-proc mp_ws_open export;
  dcl-pi *n;
    ws         likeds(mp_WebSocket_t);
    host       varchar(255) const;
    port       int(10) value;
    path       varchar(256) const;
    authHeader varchar(1024) const;
    cfg        likeds(mp_TlsConfig_t) const;
  end-pi;
  dcl-s  keyRaw char(16);
  dcl-ds key    likeds(mp_Buffer_t) inz;
  dcl-ds req    likeds(mp_Buffer_t) inz;
  dcl-ds acc    likeds(mp_Buffer_t) inz;
  dcl-ds want   likeds(mp_Buffer_t) inz;
  dcl-s  hdrLen int(10);
  dcl-s  hdr    varchar(MP_VALUE_MAX:4);
  dcl-s  status varchar(256);
  dcl-s  accept varchar(256);
  dcl-s  digest char(20);
  dcl-s  eol    int(10);

  clear ws;
  mp_trans_open(ws.trans : host : port : cfg);

  monitor;
    // Sec-WebSocket-Key: base64 of 16 random bytes
    mp_random(%addr(keyRaw) : 16);
    mp_base64Encode(%addr(keyRaw) : 16 : key);

    addLine(req : 'GET ' + path + ' HTTP/1.1');
    addLine(req : 'Host: ' + %trim(host) + ':' + %char(port));
    addLine(req : 'Upgrade: websocket');
    addLine(req : 'Connection: Upgrade');
    mp_buf_addText(req : 'Sec-WebSocket-Key: ');
    mp_buf_addBytes(req : key.data : key.len);
    addCrLf(req);
    addLine(req : 'Sec-WebSocket-Version: 13');
    if authHeader <> '';
      addLine(req : 'Authorization: ' + authHeader);
    endif;
    addLine(req : 'User-Agent: mapepire-rpg');
    addCrLf(req);
    mp_trans_write(ws.trans : req.data : req.len);

    // read until the end of the HTTP header
    hdrLen = 0;
    dow hdrLen = 0;
      if not fill(ws : ws.rbuf.len - ws.rpos + 1 : *on);
        mp_throw('Mapepire: connection closed during the WebSocket '
                 + 'handshake');
      endif;
      hdrLen = findHeaderEnd(ws.rbuf);
      if hdrLen = 0 and ws.rbuf.len > 65536;
        mp_throw('Mapepire: invalid response to the WebSocket handshake');
      endif;
    enddo;

    hdr = mp_utf8ToText(ws.rbuf.data : hdrLen);
    eol = %scan(x'0D' : hdr);
    if eol = 0;
      eol = %len(hdr) + 1;
    endif;
    status = %subst(hdr : 1 : %min(eol - 1 : 256));
    if %scan(' 101' : status) = 0;
      if %scan(' 401' : status) > 0;
        mp_throw('Mapepire: authentication failed (' + status + ')');
      endif;
      mp_throw('Mapepire: WebSocket upgrade refused (' + status + ')');
    endif;

    // Sec-WebSocket-Accept = base64(SHA-1(key + GUID))
    mp_buf_addBytes(acc : key.data : key.len);
    mp_buf_addText(acc : WS_GUID);
    digest = mp_sha1(acc.data : acc.len);
    mp_base64Encode(%addr(digest) : 20 : want);
    accept = headerValue(hdr : 'sec-websocket-accept');
    if accept <> mp_utf8ToText(want.data : want.len);
      mp_throw('Mapepire: invalid Sec-WebSocket-Accept from the server');
    endif;

    // anything after the header already belongs to the first frame
    ws.rpos = hdrLen;
    ws.isOpen = *on;
  on-error;
    mp_buf_free(key);
    mp_buf_free(req);
    mp_buf_free(acc);
    mp_buf_free(want);
    mp_ws_close(ws);
    mp_rethrow();
  endmon;

  mp_buf_free(key);
  mp_buf_free(req);
  mp_buf_free(acc);
  mp_buf_free(want);
end-proc;

// ===========================================================================
dcl-proc mp_ws_sendText export;
  dcl-pi *n;
    ws  likeds(mp_WebSocket_t);
    ptr pointer value;
    len int(10) value;
  end-pi;
  if not ws.isOpen;
    mp_throw('Mapepire: the WebSocket is not open');
  endif;
  sendFrame(ws : OP_TEXT : ptr : len);
end-proc;

// ===========================================================================
dcl-proc mp_ws_receive export;
  dcl-pi *n;
    ws likeds(mp_WebSocket_t);
  end-pi;
  dcl-s p       pointer;
  dcl-s byte    uns(3) based(p);
  dcl-s b0      int(10);
  dcl-s b1      int(10);
  dcl-s fin     ind;
  dcl-s opcode  int(10);
  dcl-s masked  ind;
  dcl-s hdr     int(10);
  dcl-s plen    int(20);
  dcl-s i       int(10);
  dcl-s mask    uns(3) dim(4);
  dcl-s payload pointer;
  dcl-s done    ind inz(*off);
  dcl-s code    int(10);

  if not ws.isOpen;
    mp_throw('Mapepire: the WebSocket is not open');
  endif;

  // reset the message buffer (a previous message may have been handed off)
  ws.msg.len = 0;

  dow not done;
    need(ws : 2);
    p = ws.rbuf.data + ws.rpos;
    b0 = byte;
    p += 1;
    b1 = byte;
    fin = b0 >= 128;
    opcode = %rem(b0 : 16);
    masked = b1 >= 128;
    plen = %rem(b1 : 128);
    hdr = 2;
    if plen = 126;
      need(ws : 4);
      plen = 0;
      for i = 2 to 3;
        p = ws.rbuf.data + ws.rpos + i;
        plen = plen * 256 + byte;
      endfor;
      hdr = 4;
    elseif plen = 127;
      need(ws : 10);
      plen = 0;
      for i = 2 to 9;
        p = ws.rbuf.data + ws.rpos + i;
        plen = plen * 256 + byte;
      endfor;
      hdr = 10;
    endif;
    if plen > 1073741824;
      mp_ws_close(ws);
      mp_throw('Mapepire: WebSocket frame too large');
    endif;
    if masked;
      need(ws : hdr + 4);
      for i = 1 to 4;
        p = ws.rbuf.data + ws.rpos + hdr + i - 1;
        mask(i) = byte;
      endfor;
      hdr += 4;
    endif;
    need(ws : hdr + plen);
    payload = ws.rbuf.data + ws.rpos + hdr;
    if masked;
      for i = 0 to plen - 1;
        p = payload + i;
        byte = %bitxor(byte : mask(%rem(i : 4) + 1));
      endfor;
    endif;

    select;
      when opcode = OP_TEXT or opcode = OP_BIN or opcode = OP_CONT;
        mp_buf_addBytes(ws.msg : payload : plen);
        done = fin;
      when opcode = OP_PING;
        sendFrame(ws : OP_PONG : payload : plen);
      when opcode = OP_PONG;
        // nothing to do
      when opcode = OP_CLOSE;
        code = 0;
        if plen >= 2;
          p = payload;
          code = byte * 256;
          p += 1;
          code += byte;
        endif;
        ws.rpos += hdr + plen;
        mp_ws_close(ws);
        mp_throw('Mapepire: the server closed the connection (code '
                 + %char(code) + ')');
      other;
        mp_ws_close(ws);
        mp_throw('Mapepire: unexpected WebSocket opcode ' + %char(opcode));
    endsl;
    ws.rpos += hdr + plen;
  enddo;
end-proc;

// ===========================================================================
dcl-proc mp_ws_close export;
  dcl-pi *n;
    ws likeds(mp_WebSocket_t);
  end-pi;
  dcl-s code char(2) inz(x'03E8');

  if ws.isOpen;
    ws.isOpen = *off;
    // best effort close frame (1000 = normal closure)
    monitor;
      sendFrame(ws : OP_CLOSE : %addr(code) : 2);
    on-error;
    endmon;
  endif;
  mp_trans_close(ws.trans);
  mp_buf_free(ws.rbuf);
  mp_buf_free(ws.sbuf);
  mp_buf_free(ws.msg);
  ws.rpos = 0;
end-proc;

// ---------------------------------------------------------------------------
//  Build and send one masked frame
// ---------------------------------------------------------------------------
dcl-proc sendFrame;
  dcl-pi *n;
    ws     likeds(mp_WebSocket_t);
    opcode int(10) value;
    ptr    pointer value;
    len    int(10) value;
  end-pi;
  dcl-s maskKey char(4);
  dcl-s maskW   uns(10) based(pMaskKey);
  dcl-s pMaskKey pointer;
  dcl-s p       pointer;
  dcl-s w       uns(10) based(p);
  dcl-s b       uns(3) based(p);
  dcl-s pk      pointer;
  dcl-s kb      uns(3) based(pk);
  dcl-s start   int(10);
  dcl-s i       int(10);
  dcl-s n       int(20);

  ws.sbuf.len = 0;
  mp_buf_reserve(ws.sbuf : len + 14);
  mp_buf_addByte(ws.sbuf : 128 + opcode);
  if len < 126;
    mp_buf_addByte(ws.sbuf : 128 + len);
  elseif len < 65536;
    mp_buf_addByte(ws.sbuf : 128 + 126);
    mp_buf_addByte(ws.sbuf : %div(len : 256));
    mp_buf_addByte(ws.sbuf : %rem(len : 256));
  else;
    mp_buf_addByte(ws.sbuf : 128 + 127);
    n = len;
    for i = 7 downto 0;
      mp_buf_addByte(ws.sbuf : %rem(%div(n : pow256(i)) : 256));
    endfor;
  endif;
  mp_random(%addr(maskKey) : 4);
  mp_buf_addBytes(ws.sbuf : %addr(maskKey) : 4);
  start = ws.sbuf.len;
  mp_buf_addBytes(ws.sbuf : ptr : len);

  // mask the payload: whole words first, then the remaining bytes
  pMaskKey = %addr(maskKey);
  i = 0;
  dow i + 4 <= len;
    p = ws.sbuf.data + start + i;
    w = %bitxor(w : maskW);
    i += 4;
  enddo;
  dow i < len;
    p = ws.sbuf.data + start + i;
    pk = %addr(maskKey) + %rem(i : 4);
    b = %bitxor(b : kb);
    i += 1;
  enddo;

  mp_trans_write(ws.trans : ws.sbuf.data : ws.sbuf.len);
end-proc;

dcl-proc pow256;
  dcl-pi *n int(20);
    e int(10) value;
  end-pi;
  dcl-s r int(20) inz(1);
  dcl-s i int(10);
  for i = 1 to e;
    r *= 256;
  endfor;
  return r;
end-proc;

// ---------------------------------------------------------------------------
//  Make sure at least `count` unread bytes are buffered
// ---------------------------------------------------------------------------
dcl-proc need;
  dcl-pi *n;
    ws    likeds(mp_WebSocket_t);
    count int(20) value;
  end-pi;
  if not fill(ws : count : *off);
    mp_ws_close(ws);
    mp_throw('Mapepire: the connection was closed by the server');
  endif;
end-proc;

// Returns *OFF when the peer closed the connection first
dcl-proc fill;
  dcl-pi *n ind;
    ws       likeds(mp_WebSocket_t);
    count    int(20) value;
    readOnce ind value;
  end-pi;
  dcl-s avail int(10);
  dcl-s n     int(10);

  avail = ws.rbuf.len - ws.rpos;
  if avail >= count and not readOnce;
    return *on;
  endif;
  // compact: move unread bytes to the front
  if ws.rpos > 0;
    if avail > 0;
      mp_memmove(ws.rbuf.data : ws.rbuf.data + ws.rpos : avail);
    endif;
    ws.rbuf.len = avail;
    ws.rpos = 0;
  endif;
  dow ws.rbuf.len < count or readOnce;
    mp_buf_reserve(ws.rbuf : READ_CHUNK);
    n = mp_trans_read(ws.trans : ws.rbuf.data + ws.rbuf.len
                      : ws.rbuf.cap - ws.rbuf.len);
    if n <= 0;
      return *off;
    endif;
    ws.rbuf.len += n;
    readOnce = *off;
  enddo;
  return *on;
end-proc;

// Offset just past CRLFCRLF, or 0
dcl-proc findHeaderEnd;
  dcl-pi *n int(10);
    buf likeds(mp_Buffer_t) const;
  end-pi;
  dcl-s i   int(10);
  dcl-s p   pointer;
  dcl-s seq char(4) based(p);
  for i = 0 to buf.len - 4;
    p = buf.data + i;
    if seq = x'0D0A0D0A';
      return i + 4;
    endif;
  endfor;
  return 0;
end-proc;

// Value of a header (case-insensitive name), trimmed
dcl-proc headerValue;
  dcl-pi *n varchar(256);
    hdr  varchar(MP_VALUE_MAX:4) const;
    name varchar(64) const;
  end-pi;
  dcl-c LOWER 'abcdefghijklmnopqrstuvwxyz';
  dcl-c UPPER 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  dcl-s low  varchar(MP_VALUE_MAX:4);
  dcl-s pos  int(10);
  dcl-s eol  int(10);
  low = %xlate(UPPER : LOWER : hdr);
  pos = %scan(x'0D25' + %xlate(UPPER : LOWER : name) + ':' : low);
  if pos = 0;
    return '';
  endif;
  pos += 2 + %len(name) + 1;
  eol = %scan(x'0D' : hdr : pos);
  if eol = 0;
    eol = %len(hdr) + 1;
  endif;
  return %trim(%subst(hdr : pos : eol - pos));
end-proc;

dcl-proc addLine;
  dcl-pi *n;
    buf  likeds(mp_Buffer_t);
    text varchar(2048) const;
  end-pi;
  mp_buf_addText(buf : text);
  addCrLf(buf);
end-proc;

dcl-proc addCrLf;
  dcl-pi *n;
    buf likeds(mp_Buffer_t);
  end-pi;
  mp_buf_addByte(buf : 13);
  mp_buf_addByte(buf : 10);
end-proc;

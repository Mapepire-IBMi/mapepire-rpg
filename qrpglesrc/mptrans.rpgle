**FREE
// ===========================================================================
//  MPTRANS - TCP and TLS (GSKit) transport
//
//  Server certificate verification:
//    - pinned certificate: GSKit handshake in pass-through mode, then the
//      partner certificate (DER) must be byte-for-byte identical to the
//      pinned one.
//    - ignoreUnauthorized: pass-through, no check.
//    - default: GSKit full validation against the *SYSTEM store, then the
//      host name is matched against the certificate's DNS names / CN.
// ===========================================================================
ctl-opt nomain ccsid(*char:*jobrun) alloc(*teraspace)
        option(*srcstmt:*nodebugio) bnddir('QC2LE':'QUSAPIBD');
// QC2LE: C runtime and sockets; QUSAPIBD: GSKit (QSYS/QSOSSLSR)

/copy mpint.rpgleinc

// ---------------------------------------------------------------------------
//  Sockets
// ---------------------------------------------------------------------------
dcl-c AF_UNSPEC   0;
dcl-c SOCK_STREAM 1;
dcl-c SOL_SOCKET  -1;
dcl-c SO_RCVTIMEO 50;

dcl-ds addrinfo_t qualified template inz;
  flags     int(10) pos(1);
  family    int(10) pos(5);
  socktype  int(10) pos(9);
  protocol  int(10) pos(13);
  addrlen   int(10) pos(17);
  canonname pointer pos(33);
  addr      pointer pos(49);
  nxt       pointer pos(65);
  eflags    int(10) pos(81);
  filler    char(12) pos(85);
end-ds;

dcl-pr getaddrinfo int(10) extproc('getaddrinfo');
  node    pointer value options(*string);
  service pointer value options(*string);
  hints   pointer value;
  res     pointer;
end-pr;

dcl-pr freeaddrinfo extproc('freeaddrinfo');
  res pointer value;
end-pr;

dcl-pr gai_strerror pointer extproc('gai_strerror');
  ecode int(10) value;
end-pr;

dcl-pr c_socket int(10) extproc('socket');
  domain   int(10) value;
  type     int(10) value;
  protocol int(10) value;
end-pr;

dcl-pr c_connect int(10) extproc('connect');
  sd      int(10) value;
  addr    pointer value;
  addrlen int(10) value;
end-pr;

dcl-pr c_send int(10) extproc('send');
  sd    int(10) value;
  buf   pointer value;
  len   int(10) value;
  flags int(10) value;
end-pr;

dcl-pr c_recv int(10) extproc('recv');
  sd    int(10) value;
  buf   pointer value;
  len   int(10) value;
  flags int(10) value;
end-pr;

dcl-pr c_setsockopt int(10) extproc('setsockopt');
  sd      int(10) value;
  level   int(10) value;
  optname int(10) value;
  optval  pointer value;
  optlen  int(10) value;
end-pr;

dcl-pr c_close int(10) extproc('close');
  sd int(10) value;
end-pr;

// ---------------------------------------------------------------------------
//  GSKit (QSYS/QSOSSLSR)
// ---------------------------------------------------------------------------
dcl-c GSK_OK                         0;
dcl-c GSK_KEYRING_FILE               201;
dcl-c GSK_SSL_EXTN_SERVERNAME_REQUEST 230;
dcl-c GSK_FD                         300;
dcl-c GSK_IBMI_READ_TIMEOUT          6993;
dcl-c GSK_HANDSHAKE_TIMEOUT          6998;
dcl-c GSK_SESSION_TYPE               402;
dcl-c GSK_SERVER_AUTH_TYPE           410;
dcl-c GSK_CLIENT_SESSION             507;
dcl-c GSK_SERVER_AUTH_FULL           534;
dcl-c GSK_SERVER_AUTH_PASSTHRU       535;
dcl-c GSK_PARTNER_CERT_INFO          700;
dcl-c CERT_BODY_DER                  600;
dcl-c CERT_COMMON_NAME               610;
dcl-c CERT_SAN_DNSNAME               673;
dcl-c GSK_ERROR_SOCKET_CLOSED        420;
dcl-c GSK_IBMI_ERROR_TIMED_OUT       6011;

// gsk_cert_data_elem: enum (4) + pad, char* at 16, int at 32; size 48
dcl-ds certElem_t qualified template inz;
  id  int(10) pos(1);
  ptr pointer pos(17);
  len int(10) pos(33);
end-ds;
dcl-c CERT_ELEM_SIZE 48;

dcl-pr gsk_environment_open int(10) extproc('gsk_environment_open');
  env pointer;
end-pr;

dcl-pr gsk_environment_init int(10) extproc('gsk_environment_init');
  env pointer value;
end-pr;

dcl-pr gsk_environment_close int(10) extproc('gsk_environment_close');
  env pointer;
end-pr;

dcl-pr gsk_attribute_set_buffer int(10)
       extproc('gsk_attribute_set_buffer');
  handle pointer value;
  id     int(10) value;
  buf    pointer value options(*string);
  len    int(10) value;
end-pr;

dcl-pr gsk_attribute_set_enum int(10) extproc('gsk_attribute_set_enum');
  handle pointer value;
  id     int(10) value;
  value  int(10) value;
end-pr;

dcl-pr gsk_attribute_set_numeric_value int(10)
       extproc('gsk_attribute_set_numeric_value');
  handle pointer value;
  id     int(10) value;
  value  int(10) value;
end-pr;

dcl-pr gsk_attribute_get_cert_info int(10)
       extproc('gsk_attribute_get_cert_info');
  handle pointer value;
  id     int(10) value;
  elems  pointer;
  count  int(10);
end-pr;

dcl-pr gsk_secure_soc_open int(10) extproc('gsk_secure_soc_open');
  env pointer value;
  soc pointer;
end-pr;

dcl-pr gsk_secure_soc_init int(10) extproc('gsk_secure_soc_init');
  soc pointer value;
end-pr;

dcl-pr gsk_secure_soc_read int(10) extproc('gsk_secure_soc_read');
  soc    pointer value;
  buf    pointer value;
  size   int(10) value;
  amount int(10);
end-pr;

dcl-pr gsk_secure_soc_write int(10) extproc('gsk_secure_soc_write');
  soc    pointer value;
  buf    pointer value;
  size   int(10) value;
  amount int(10);
end-pr;

dcl-pr gsk_secure_soc_close int(10) extproc('gsk_secure_soc_close');
  soc pointer;
end-pr;

dcl-pr gsk_strerror pointer extproc('gsk_strerror');
  rc int(10) value;
end-pr;

// ===========================================================================
dcl-proc mp_trans_open export;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
    host  varchar(255) const;
    port  int(10) value;
    cfg   likeds(mp_TlsConfig_t) const;
  end-pi;
  dcl-ds hints likeds(addrinfo_t) inz;
  dcl-ds ai    likeds(addrinfo_t) based(pAi);
  dcl-s  pAi   pointer;
  dcl-s  pRes  pointer;
  dcl-s  rc    int(10);
  dcl-s  sd    int(10) inz(-1);
  dcl-s  lastErr varchar(256);
  dcl-ds tv    qualified;
    sec  int(10);
    usec int(10);
  end-ds;

  clear trans;
  trans.sd = -1;

  hints.family = AF_UNSPEC;
  hints.socktype = SOCK_STREAM;
  rc = getaddrinfo(%trim(host) : %char(port) : %addr(hints) : pRes);
  if rc <> 0;
    mp_throw('Mapepire: cannot resolve host ' + %trim(host) + ': '
             + %str(gai_strerror(rc)));
  endif;

  // try every address until one connects
  pAi = pRes;
  dow pAi <> *null;
    sd = c_socket(ai.family : ai.socktype : ai.protocol);
    if sd >= 0;
      if c_connect(sd : ai.addr : ai.addrlen) = 0;
        leave;
      endif;
      lastErr = mp_errnoText();
      c_close(sd);
      sd = -1;
    else;
      lastErr = mp_errnoText();
    endif;
    pAi = ai.nxt;
  enddo;
  freeaddrinfo(pRes);
  if sd < 0;
    mp_throw('Mapepire: cannot connect to ' + %trim(host) + ':'
             + %char(port) + ': ' + lastErr);
  endif;
  trans.sd = sd;

  if not cfg.useTls;
    if cfg.timeoutSecs > 0;
      tv.sec = cfg.timeoutSecs;
      tv.usec = 0;
      c_setsockopt(sd : SOL_SOCKET : SO_RCVTIMEO : %addr(tv) : %size(tv));
    endif;
    trans.isOpen = *on;
    return;
  endif;

  monitor;
    startTls(trans : host : cfg);
  on-error;
    mp_trans_close(trans);
    mp_rethrow();
  endmon;
  trans.isOpen = *on;
end-proc;

// ---------------------------------------------------------------------------
dcl-proc startTls;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
    host  varchar(255) const;
    cfg   likeds(mp_TlsConfig_t) const;
  end-pi;
  dcl-s rc       int(10);
  dcl-s pinned   ind;
  dcl-s authType int(10);

  trans.tls = *on;
  pinned = cfg.pinnedDer.len > 0;
  if pinned or cfg.ignoreUnauthorized;
    authType = GSK_SERVER_AUTH_PASSTHRU;
  else;
    authType = GSK_SERVER_AUTH_FULL;
  endif;

  rc = gsk_environment_open(trans.env);
  gskCheck(rc : 'gsk_environment_open');
  rc = gsk_attribute_set_buffer(trans.env : GSK_KEYRING_FILE : '*SYSTEM' : 0);
  gskCheck(rc : 'set GSK_KEYRING_FILE');
  rc = gsk_attribute_set_enum(trans.env : GSK_SESSION_TYPE
                              : GSK_CLIENT_SESSION);
  gskCheck(rc : 'set GSK_SESSION_TYPE');
  rc = gsk_attribute_set_enum(trans.env : GSK_SERVER_AUTH_TYPE : authType);
  gskCheck(rc : 'set GSK_SERVER_AUTH_TYPE');
  rc = gsk_environment_init(trans.env);
  gskCheck(rc : 'gsk_environment_init');

  rc = gsk_secure_soc_open(trans.env : trans.soc);
  gskCheck(rc : 'gsk_secure_soc_open');
  rc = gsk_attribute_set_numeric_value(trans.soc : GSK_FD : trans.sd);
  gskCheck(rc : 'set GSK_FD');
  // SNI - best effort
  gsk_attribute_set_buffer(trans.soc : GSK_SSL_EXTN_SERVERNAME_REQUEST
                           : %trim(host) : 0);
  if cfg.timeoutSecs > 0;
    gsk_attribute_set_numeric_value(trans.soc : GSK_HANDSHAKE_TIMEOUT
                                    : cfg.timeoutSecs);
    gsk_attribute_set_numeric_value(trans.soc : GSK_IBMI_READ_TIMEOUT
                                    : cfg.timeoutSecs * 1000);
  endif;

  rc = gsk_secure_soc_init(trans.soc);
  gskCheck(rc : 'TLS handshake with ' + %trim(host));

  if pinned;
    checkPinned(trans : cfg.pinnedDer);
  elseif not cfg.ignoreUnauthorized;
    checkHostName(trans : host);
  endif;
end-proc;

// ---------------------------------------------------------------------------
//  The partner certificate must equal the pinned DER exactly
// ---------------------------------------------------------------------------
dcl-proc checkPinned;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
    der   likeds(mp_Buffer_t) const;
  end-pi;
  dcl-s pElems pointer;
  dcl-s count  int(10);
  dcl-s i      int(10);
  dcl-s rc     int(10);
  dcl-ds el likeds(certElem_t) based(pEl);
  dcl-s pEl pointer;

  rc = gsk_attribute_get_cert_info(trans.soc : GSK_PARTNER_CERT_INFO
                                   : pElems : count);
  gskCheck(rc : 'reading the server certificate');
  for i = 0 to count - 1;
    pEl = pElems + i * CERT_ELEM_SIZE;
    if el.id = CERT_BODY_DER;
      if el.len = der.len and mp_memcmp(el.ptr : der.data : der.len) = 0;
        return;
      endif;
      leave;
    endif;
  endfor;
  mp_throw('Mapepire: the server certificate does not match the trusted '
           + 'certificate (ca / caFile)');
end-proc;

// ---------------------------------------------------------------------------
//  Host name verification (RFC 6125): the DNS names of the subjectAltName
//  extension, or the subject CN when there are none; leftmost-label
//  wildcards allowed.
//
//  GSKit only reports the FIRST subjectAltName DNS name, so the extension
//  is read from the certificate DER instead.
// ---------------------------------------------------------------------------
dcl-proc checkHostName;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
    host  varchar(255) const;
  end-pi;
  dcl-s pElems  pointer;
  dcl-s count   int(10);
  dcl-s i       int(10);
  dcl-s rc      int(10);
  dcl-s cn      varchar(255) inz('');
  dcl-s seen    varchar(512) inz('');
  dcl-s names   varchar(255) dim(256);
  dcl-s nNames  int(10) inz(0);
  dcl-s derP    pointer inz(*null);
  dcl-s derL    int(10) inz(0);
  dcl-ds el likeds(certElem_t) based(pEl);
  dcl-s pEl pointer;

  rc = gsk_attribute_get_cert_info(trans.soc : GSK_PARTNER_CERT_INFO
                                   : pElems : count);
  gskCheck(rc : 'reading the server certificate');
  for i = 0 to count - 1;
    pEl = pElems + i * CERT_ELEM_SIZE;
    if el.ptr = *null or el.len <= 0;
      iter;
    endif;
    select;
      when el.id = CERT_BODY_DER;
        derP = el.ptr;
        derL = el.len;
      when el.id = CERT_COMMON_NAME and el.len <= 255;
        // GSKit returns these fields as ASCII text
        cn = mp_utf8ToText(el.ptr : el.len);
      when el.id = CERT_SAN_DNSNAME and el.len <= 255 and nNames = 0;
        // fallback only; replaced by the full list from the DER below
        nNames = 1;
        names(1) = mp_utf8ToText(el.ptr : el.len);
    endsl;
  endfor;
  if derP <> *null;
    sanDnsNames(derP : derL : names : nNames);
  endif;

  for i = 1 to nNames;
    if hostMatches(host : names(i));
      return;
    endif;
    if %len(seen) < 400;
      seen += ' ' + names(i);
    endif;
  endfor;
  if nNames = 0 and cn <> '';
    if hostMatches(host : cn);
      return;
    endif;
    seen = ' ' + cn;
  endif;
  mp_throw('Mapepire: the server certificate is not valid for host '
           + %trim(host) + ' (certificate names:' + seen + ')');
end-proc;

// DNS names of the subjectAltName extension (OID 2.5.29.17) of a DER
// certificate. Leaves names/count untouched when there is no extension.
dcl-proc sanDnsNames;
  dcl-pi *n;
    der   pointer value;
    len   int(10) value;
    names varchar(255) dim(256);
    count int(10);
  end-pi;
  dcl-s oid   char(5) inz(x'0603551D11');
  dcl-s i     int(10);
  dcl-s p     pointer;
  dcl-s endP  pointer;
  dcl-s b     uns(3) based(p);
  dcl-s cmp   char(5) based(p);
  dcl-s tag   int(10);
  dcl-s l     int(10);
  dcl-s found ind inz(*off);
  dcl-s n     int(10) inz(0);

  for i = 0 to len - 5;
    p = der + i;
    if cmp = oid;
      found = *on;
      leave;
    endif;
  endfor;
  if not found;
    return;
  endif;
  p += 5;
  endP = der + len;
  // optional "critical" BOOLEAN
  if b = 1;
    p += 3;
  endif;
  // OCTET STRING wrapping the extension value
  if p >= endP or b <> 4;
    return;
  endif;
  p += 1;
  l = derLength(p : endP);
  // SEQUENCE OF GeneralName
  if p >= endP or b <> 48;
    return;
  endif;
  p += 1;
  l = derLength(p : endP);
  if l < 0 or p + l > endP;
    return;
  endif;
  endP = p + l;
  dow p < endP and n < %elem(names);
    tag = b;
    p += 1;
    l = derLength(p : endP);
    if l < 0 or p + l > endP;
      leave;
    endif;
    // [2] IMPLICIT IA5String = dNSName
    if tag = 130 and l > 0 and l <= 255;
      n += 1;
      names(n) = mp_utf8ToText(p : l);
    endif;
    p += l;
  enddo;
  if n > 0;
    count = n;
  endif;
end-proc;

// Read a DER length at p (advancing p); -1 when malformed
dcl-proc derLength;
  dcl-pi *n int(10);
    p    pointer;
    endP pointer value;
  end-pi;
  dcl-s b uns(3) based(p);
  dcl-s n int(10);
  dcl-s l int(10) inz(0);
  dcl-s i int(10);
  if p >= endP;
    return -1;
  endif;
  if b < 128;
    l = b;
    p += 1;
    return l;
  endif;
  n = b - 128;
  p += 1;
  if n < 1 or n > 3 or p + n > endP;
    return -1;
  endif;
  for i = 1 to n;
    l = l * 256 + b;
    p += 1;
  endfor;
  return l;
end-proc;

dcl-proc hostMatches;
  dcl-pi *n ind;
    host    varchar(255) const;
    pattern varchar(255) const;
  end-pi;
  dcl-c LOWER 'abcdefghijklmnopqrstuvwxyz';
  dcl-c UPPER 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  dcl-s h   varchar(255);
  dcl-s p   varchar(255);
  dcl-s dot int(10);

  h = %xlate(UPPER : LOWER : %trim(host));
  p = %xlate(UPPER : LOWER : %trim(pattern));
  if h = p;
    return *on;
  endif;
  // *.example.com matches exactly one extra leftmost label
  if %len(p) > 2 and %subst(p : 1 : 2) = '*.';
    dot = %scan('.' : h);
    if dot > 1 and %subst(h : dot) = %subst(p : 2);
      return *on;
    endif;
  endif;
  return *off;
end-proc;

// ---------------------------------------------------------------------------
dcl-proc gskCheck;
  dcl-pi *n;
    rc   int(10) value;
    what varchar(256) const;
  end-pi;
  if rc = GSK_OK;
    return;
  endif;
  mp_throw('Mapepire: TLS error in ' + what + ': ' + %str(gsk_strerror(rc))
           + ' (GSK rc ' + %char(rc) + ')');
end-proc;

// ===========================================================================
dcl-proc mp_trans_write export;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
    ptr   pointer value;
    len   int(10) value;
  end-pi;
  dcl-s done   int(10) inz(0);
  dcl-s amount int(10);
  dcl-s rc     int(10);

  if not trans.isOpen;
    mp_throw('Mapepire: the connection is closed');
  endif;
  dow done < len;
    if trans.tls;
      amount = 0;
      rc = gsk_secure_soc_write(trans.soc : ptr + done : len - done : amount);
      if rc <> GSK_OK;
        mp_trans_close(trans);
        mp_throw('Mapepire: TLS write failed: ' + %str(gsk_strerror(rc)));
      endif;
    else;
      amount = c_send(trans.sd : ptr + done : len - done : 0);
      if amount < 0;
        lastErrClose(trans : 'send failed');
      endif;
    endif;
    done += amount;
  enddo;
end-proc;

dcl-proc mp_trans_read export;
  dcl-pi *n int(10);
    trans likeds(mp_Transport_t);
    ptr   pointer value;
    len   int(10) value;
  end-pi;
  dcl-s amount int(10) inz(0);
  dcl-s rc     int(10);

  if not trans.isOpen;
    return 0;
  endif;
  if trans.tls;
    rc = gsk_secure_soc_read(trans.soc : ptr : len : amount);
    if rc = GSK_ERROR_SOCKET_CLOSED;
      return 0;
    endif;
    if rc = GSK_IBMI_ERROR_TIMED_OUT;
      mp_throw('Mapepire: timed out waiting for the server');
    endif;
    if rc <> GSK_OK;
      mp_trans_close(trans);
      mp_throw('Mapepire: TLS read failed: ' + %str(gsk_strerror(rc)));
    endif;
  else;
    amount = c_recv(trans.sd : ptr : len : 0);
    if amount < 0;
      lastErrClose(trans : 'receive failed');
    endif;
  endif;
  return amount;
end-proc;

dcl-proc lastErrClose;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
    what  varchar(64) const;
  end-pi;
  dcl-s text varchar(256);
  text = mp_errnoText();
  mp_trans_close(trans);
  mp_throw('Mapepire: ' + what + ': ' + text);
end-proc;

dcl-proc mp_trans_close export;
  dcl-pi *n;
    trans likeds(mp_Transport_t);
  end-pi;
  if trans.soc <> *null;
    gsk_secure_soc_close(trans.soc);
    trans.soc = *null;
  endif;
  if trans.env <> *null;
    gsk_environment_close(trans.env);
    trans.env = *null;
  endif;
  if trans.sd >= 0;
    c_close(trans.sd);
    trans.sd = -1;
  endif;
  trans.isOpen = *off;
end-proc;

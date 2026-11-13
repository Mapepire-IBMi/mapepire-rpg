**FREE
// ===========================================================================
//  MPJSON - JSON writer and parser working directly on UTF-8 bytes
//
//  The parser builds a flat node table (no recursion, no copies of the
//  source text): each node records its type, the byte span of its key and
//  value inside the source, and parent / first child / next sibling links.
//  Strings are only unescaped / converted when a value is asked for.
// ===========================================================================
ctl-opt nomain ccsid(*char:*jobrun) alloc(*teraspace)
        option(*srcstmt:*nodebugio) bnddir('QC2LE');

/copy mpint.rpgleinc

// ASCII
dcl-c C_QUOTE   34;
dcl-c C_BSLASH  92;
dcl-c C_SLASH   47;
dcl-c C_COMMA   44;
dcl-c C_COLON   58;
dcl-c C_LBRACE  123;
dcl-c C_RBRACE  125;
dcl-c C_LBRACK  91;
dcl-c C_RBRACK  93;
dcl-c C_MINUS   45;
dcl-c C_PLUS    43;
dcl-c C_DOT     46;
dcl-c C_0       48;
dcl-c C_9       57;
dcl-c C_LOWER_E 101;
dcl-c C_UPPER_E 69;
dcl-c C_T       116;
dcl-c C_F       102;
dcl-c C_N       110;

dcl-c NODE_SIZE 40;

// ===========================================================================
//  Writer
// ===========================================================================
dcl-proc beforeValue;
  dcl-pi *n;
    w likeds(mp_JsonWriter_t);
  end-pi;
  if w.afterKey;
    w.afterKey = *off;
    return;
  endif;
  if w.depth > 0;
    if w.cnt(w.depth) > 0;
      mp_buf_addByte(w.buf : C_COMMA);
    endif;
    w.cnt(w.depth) += 1;
  endif;
end-proc;

dcl-proc mp_jw_beginObject export;
  dcl-pi *n;
    w likeds(mp_JsonWriter_t);
  end-pi;
  beforeValue(w);
  mp_buf_addByte(w.buf : C_LBRACE);
  w.depth += 1;
  w.cnt(w.depth) = 0;
end-proc;

dcl-proc mp_jw_endObject export;
  dcl-pi *n;
    w likeds(mp_JsonWriter_t);
  end-pi;
  mp_buf_addByte(w.buf : C_RBRACE);
  w.depth -= 1;
end-proc;

dcl-proc mp_jw_beginArray export;
  dcl-pi *n;
    w likeds(mp_JsonWriter_t);
  end-pi;
  beforeValue(w);
  mp_buf_addByte(w.buf : C_LBRACK);
  w.depth += 1;
  w.cnt(w.depth) = 0;
end-proc;

dcl-proc mp_jw_endArray export;
  dcl-pi *n;
    w likeds(mp_JsonWriter_t);
  end-pi;
  mp_buf_addByte(w.buf : C_RBRACK);
  w.depth -= 1;
end-proc;

dcl-proc mp_jw_key export;
  dcl-pi *n;
    w    likeds(mp_JsonWriter_t);
    name varchar(256) const;
  end-pi;
  beforeValue(w);
  mp_json_quoteText(w.buf : name);
  mp_buf_addByte(w.buf : C_COLON);
  w.afterKey = *on;
end-proc;

dcl-proc mp_jw_string export;
  dcl-pi *n;
    w     likeds(mp_JsonWriter_t);
    value varchar(MP_SQL_MAX:4) const;
  end-pi;
  beforeValue(w);
  mp_json_quoteText(w.buf : value);
end-proc;

dcl-proc mp_jw_stringUtf8 export;
  dcl-pi *n;
    w   likeds(mp_JsonWriter_t);
    ptr pointer value;
    len int(10) value;
  end-pi;
  beforeValue(w);
  mp_json_quoteUtf8(w.buf : ptr : len);
end-proc;

dcl-proc mp_jw_int export;
  dcl-pi *n;
    w     likeds(mp_JsonWriter_t);
    value int(20) value;
  end-pi;
  beforeValue(w);
  mp_buf_addText(w.buf : %char(value));
end-proc;

dcl-proc mp_jw_bool export;
  dcl-pi *n;
    w     likeds(mp_JsonWriter_t);
    value ind value;
  end-pi;
  beforeValue(w);
  if value;
    mp_buf_addText(w.buf : 'true');
  else;
    mp_buf_addText(w.buf : 'false');
  endif;
end-proc;

dcl-proc mp_jw_null export;
  dcl-pi *n;
    w likeds(mp_JsonWriter_t);
  end-pi;
  beforeValue(w);
  mp_buf_addText(w.buf : 'null');
end-proc;

dcl-proc mp_jw_rawUtf8 export;
  dcl-pi *n;
    w   likeds(mp_JsonWriter_t);
    ptr pointer value;
    len int(10) value;
  end-pi;
  beforeValue(w);
  mp_buf_addBytes(w.buf : ptr : len);
end-proc;

dcl-proc mp_jw_strField export;
  dcl-pi *n;
    w     likeds(mp_JsonWriter_t);
    name  varchar(256) const;
    value varchar(MP_SQL_MAX:4) const;
  end-pi;
  mp_jw_key(w : name);
  mp_jw_string(w : value);
end-proc;

dcl-proc mp_jw_intField export;
  dcl-pi *n;
    w     likeds(mp_JsonWriter_t);
    name  varchar(256) const;
    value int(20) value;
  end-pi;
  mp_jw_key(w : name);
  mp_jw_int(w : value);
end-proc;

dcl-proc mp_jw_boolField export;
  dcl-pi *n;
    w     likeds(mp_JsonWriter_t);
    name  varchar(256) const;
    value ind value;
  end-pi;
  mp_jw_key(w : name);
  mp_jw_bool(w : value);
end-proc;

// ---------------------------------------------------------------------------
dcl-proc mp_json_quoteText export;
  dcl-pi *n;
    buf  likeds(mp_Buffer_t);
    text varchar(MP_SQL_MAX:4) const;
  end-pi;
  dcl-ds u likeds(mp_Buffer_t) inz;
  mp_buf_addText(u : text);
  mp_json_quoteUtf8(buf : u.data : u.len);
  mp_buf_free(u);
end-proc;

dcl-proc mp_json_quoteUtf8 export;
  dcl-pi *n;
    buf likeds(mp_Buffer_t);
    ptr pointer value;
    len int(10) value;
  end-pi;
  dcl-c HEX '0123456789abcdef';
  dcl-s p     pointer;
  dcl-s c     uns(3) based(p);
  dcl-s i     int(10);
  dcl-s run   int(10);
  dcl-s esc   varchar(8);

  mp_buf_reserve(buf : len + 2);
  mp_buf_addByte(buf : C_QUOTE);
  run = 0;
  for i = 0 to len - 1;
    p = ptr + i;
    if c <> C_QUOTE and c <> C_BSLASH and c >= 32;
      iter;
    endif;
    // flush the plain run before this byte
    if i > run;
      mp_buf_addBytes(buf : ptr + run : i - run);
    endif;
    run = i + 1;
    select;
      when c = C_QUOTE;
        esc = '\"';
      when c = C_BSLASH;
        esc = '\\';
      when c = 10;
        esc = '\n';
      when c = 13;
        esc = '\r';
      when c = 9;
        esc = '\t';
      other;
        esc = '\u00' + %subst(HEX : %div(c : 16) + 1 : 1)
                     + %subst(HEX : %rem(c : 16) + 1 : 1);
    endsl;
    mp_buf_addText(buf : esc);
  endfor;
  if len > run;
    mp_buf_addBytes(buf : ptr + run : len - run);
  endif;
  mp_buf_addByte(buf : C_QUOTE);
end-proc;

// ===========================================================================
//  Parser
// ===========================================================================
dcl-proc mp_json_parse export;
  dcl-pi *n;
    doc likeds(mp_JsonDoc_t);
    buf likeds(mp_Buffer_t);
  end-pi;
  dcl-c ST_VALUE 1;
  dcl-c ST_KEY   2;
  dcl-c ST_AFTER 3;
  dcl-s base    pointer;
  dcl-s p       pointer;
  dcl-s c       uns(3) based(p);
  dcl-s pos     int(10);
  dcl-s len     int(10);
  dcl-s state   int(10);
  dcl-s top     int(10) inz(0);
  dcl-s cur     int(10);
  dcl-s keyPos  int(10) inz(0);
  dcl-s keyLen  int(10) inz(0);
  dcl-s keyEsc  int(3) inz(0);
  dcl-s sPos    int(10);
  dcl-s sLen    int(10);
  dcl-s sEsc    int(3);
  dcl-s done    ind inz(*off);
  dcl-ds n      likeds(mp_JsonNode_t) based(pn);
  dcl-s pn      pointer;
  dcl-ds t      likeds(mp_JsonNode_t) based(pt);
  dcl-s pt      pointer;

  mp_json_free(doc);
  doc.src = buf.data;
  doc.srcLen = buf.len;
  doc.srcCap = buf.cap;
  buf.data = *null;
  buf.len = 0;
  buf.cap = 0;

  base = doc.src;
  len = doc.srcLen;
  pos = 0;
  state = ST_VALUE;

  dow not done;
    // skip white space
    dow pos < len;
      p = base + pos;
      if c <> 32 and c <> 9 and c <> 10 and c <> 13;
        leave;
      endif;
      pos += 1;
    enddo;
    if pos >= len;
      parseError(doc : 'unexpected end of input' : pos);
    endif;
    p = base + pos;

    select;
    // ---------------------------------------------------------------- key
    when state = ST_KEY;
      pt = nodeAt(doc : top);
      if c = C_RBRACE and t.count = 0;
        pos += 1;
        t.valLen = pos - t.valPos;
        top = t.parent;
        state = ST_AFTER;
        if top = 0;
          done = *on;
        endif;
      elseif c = C_QUOTE;
        scanString(doc : pos : sPos : sLen : sEsc);
        keyPos = sPos;
        keyLen = sLen;
        keyEsc = sEsc;
        dow pos < len;
          p = base + pos;
          if c <> 32 and c <> 9 and c <> 10 and c <> 13;
            leave;
          endif;
          pos += 1;
        enddo;
        p = base + pos;
        if pos >= len or c <> C_COLON;
          parseError(doc : 'expected :' : pos);
        endif;
        pos += 1;
        state = ST_VALUE;
      else;
        parseError(doc : 'expected a member name' : pos);
      endif;

    // -------------------------------------------------------------- value
    when state = ST_VALUE;
      if c = C_RBRACK and top > 0;
        pt = nodeAt(doc : top);
        if t.type = MP_JSON_ARRAY and t.count = 0;
          pos += 1;
          t.valLen = pos - t.valPos;
          top = t.parent;
          state = ST_AFTER;
          if top = 0;
            done = *on;
          endif;
          iter;
        endif;
      endif;

      cur = newNode(doc : top);
      pn = nodeAt(doc : cur);
      if top > 0;
        pt = nodeAt(doc : top);
        if t.type = MP_JSON_OBJECT;
          n.keyPos = keyPos;
          n.keyLen = keyLen;
          n.keyEsc = keyEsc;
        endif;
      endif;
      n.valPos = pos;

      select;
      when c = C_LBRACE;
        n.type = MP_JSON_OBJECT;
        pos += 1;
        top = cur;
        state = ST_KEY;
      when c = C_LBRACK;
        n.type = MP_JSON_ARRAY;
        pos += 1;
        top = cur;
        state = ST_VALUE;
      when c = C_QUOTE;
        scanString(doc : pos : sPos : sLen : sEsc);
        pn = nodeAt(doc : cur);
        n.type = MP_JSON_STRING;
        n.valPos = sPos;
        n.valLen = sLen;
        n.valEsc = sEsc;
        state = ST_AFTER;
      when c = C_T;
        expectWord(doc : pos : 'true');
        n.type = MP_JSON_TRUE;
        n.valLen = 4;
        state = ST_AFTER;
      when c = C_F;
        expectWord(doc : pos : 'false');
        n.type = MP_JSON_FALSE;
        n.valLen = 5;
        state = ST_AFTER;
      when c = C_N;
        expectWord(doc : pos : 'null');
        n.type = MP_JSON_NULL;
        n.valLen = 4;
        state = ST_AFTER;
      when c = C_MINUS or (c >= C_0 and c <= C_9);
        n.type = MP_JSON_NUMBER;
        dow pos < len;
          p = base + pos;
          if not ((c >= C_0 and c <= C_9) or c = C_MINUS or c = C_PLUS
                  or c = C_DOT or c = C_LOWER_E or c = C_UPPER_E);
            leave;
          endif;
          pos += 1;
        enddo;
        n.valLen = pos - n.valPos;
        state = ST_AFTER;
      other;
        parseError(doc : 'unexpected character' : pos);
      endsl;

      if state = ST_AFTER and top = 0;
        // a scalar document
        done = *on;
      endif;

    // -------------------------------------------------------------- after
    other;
      if top = 0;
        done = *on;
        iter;
      endif;
      pt = nodeAt(doc : top);
      if c = C_COMMA;
        pos += 1;
        if t.type = MP_JSON_OBJECT;
          state = ST_KEY;
        else;
          state = ST_VALUE;
        endif;
      elseif (c = C_RBRACE and t.type = MP_JSON_OBJECT)
          or (c = C_RBRACK and t.type = MP_JSON_ARRAY);
        pos += 1;
        t.valLen = pos - t.valPos;
        top = t.parent;
        if top = 0;
          done = *on;
        endif;
      else;
        parseError(doc : 'expected , or close bracket' : pos);
      endif;
    endsl;
  enddo;
end-proc;

// Scan a string starting at the opening quote; pos ends after the closing
// quote. Returns the content span (without quotes) and an escape flag.
dcl-proc scanString;
  dcl-pi *n;
    doc  likeds(mp_JsonDoc_t);
    pos  int(10);
    sPos int(10);
    sLen int(10);
    sEsc int(3);
  end-pi;
  dcl-s p   pointer;
  dcl-s c   uns(3) based(p);
  dcl-s q   pointer;
  dcl-s bs  pointer;
  dcl-s i   int(10);

  sPos = pos + 1;
  sEsc = 0;
  i = sPos;
  dow *on;
    if i >= doc.srcLen;
      parseError(doc : 'unterminated string' : sPos);
    endif;
    // jump to the next quote; check for backslashes in between
    q = mp_memchr(doc.src + i : C_QUOTE : doc.srcLen - i);
    if q = *null;
      parseError(doc : 'unterminated string' : sPos);
    endif;
    bs = mp_memchr(doc.src + i : C_BSLASH : q - (doc.src + i));
    if bs = *null;
      i = q - doc.src;
      leave;
    endif;
    // an escape sequence: skip the backslash and the escaped byte
    sEsc = 1;
    i = bs - doc.src + 2;
  enddo;
  sLen = i - sPos;
  pos = i + 1;
end-proc;

dcl-proc expectWord;
  dcl-pi *n;
    doc  likeds(mp_JsonDoc_t);
    pos  int(10);
    word varchar(5) const;
  end-pi;
  dcl-ds w likeds(mp_Buffer_t) inz;
  dcl-s ok ind;
  mp_buf_addText(w : word);
  ok = pos + w.len <= doc.srcLen;
  if ok;
    ok = mp_memcmp(doc.src + pos : w.data : w.len) = 0;
  endif;
  pos += w.len;
  mp_buf_free(w);
  if not ok;
    parseError(doc : 'invalid literal' : pos - %len(word));
  endif;
end-proc;

dcl-proc parseError;
  dcl-pi *n;
    doc  likeds(mp_JsonDoc_t);
    msg  varchar(128) const;
    pos  int(10) value;
  end-pi;
  mp_json_free(doc);
  mp_throw('Mapepire: invalid JSON from the server: ' + msg
           + ' at offset ' + %char(pos));
end-proc;

dcl-proc newNode;
  dcl-pi *n int(10);
    doc    likeds(mp_JsonDoc_t);
    parent int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  dcl-ds par likeds(mp_JsonNode_t) based(pp);
  dcl-s pp pointer;
  dcl-ds prev likeds(mp_JsonNode_t) based(pv);
  dcl-s pv pointer;
  dcl-s id int(10);

  if doc.count >= doc.cap;
    if doc.cap = 0;
      doc.cap = 256;
      doc.nodes = %alloc(doc.cap * NODE_SIZE);
    else;
      doc.cap *= 2;
      doc.nodes = %realloc(doc.nodes : doc.cap * NODE_SIZE);
    endif;
  endif;
  doc.count += 1;
  id = doc.count;
  pn = nodeAt(doc : id);
  clear n;
  n.parent = parent;
  if parent > 0;
    pp = nodeAt(doc : parent);
    if par.last > 0;
      pv = nodeAt(doc : par.last);
      prev.sib = id;
    else;
      par.first = id;
    endif;
    par.last = id;
    par.count += 1;
  endif;
  return id;
end-proc;

dcl-proc nodeAt;
  dcl-pi *n pointer;
    doc likeds(mp_JsonDoc_t);
    id  int(10) value;
  end-pi;
  return doc.nodes + (id - 1) * NODE_SIZE;
end-proc;

dcl-proc mp_json_free export;
  dcl-pi *n;
    doc likeds(mp_JsonDoc_t);
  end-pi;
  if doc.src <> *null;
    dealloc doc.src;
  endif;
  if doc.nodes <> *null;
    dealloc doc.nodes;
  endif;
  mp_buf_free(doc.tmp);
  clear doc;
end-proc;

// ===========================================================================
//  Navigation
// ===========================================================================
dcl-proc mp_json_type export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  if node <= 0 or node > doc.count;
    return 0;
  endif;
  pn = nodeAt(doc : node);
  return n.type;
end-proc;

dcl-proc mp_json_count export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  if node <= 0 or node > doc.count;
    return 0;
  endif;
  pn = nodeAt(doc : node);
  return n.count;
end-proc;

dcl-proc mp_json_first export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  if node <= 0 or node > doc.count;
    return 0;
  endif;
  pn = nodeAt(doc : node);
  return n.first;
end-proc;

dcl-proc mp_json_next export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  if node <= 0 or node > doc.count;
    return 0;
  endif;
  pn = nodeAt(doc : node);
  return n.sib;
end-proc;

dcl-proc mp_json_member export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
    name varchar(256) const;
  end-pi;
  dcl-ds u likeds(mp_Buffer_t) inz;
  dcl-s r int(10);
  mp_buf_addText(u : name);
  r = mp_json_memberUtf8(doc : node : u.data : u.len);
  mp_buf_free(u);
  return r;
end-proc;

dcl-proc mp_json_memberUtf8 export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
    ptr  pointer value;
    len  int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  dcl-ds c likeds(mp_JsonNode_t) based(pc);
  dcl-s pc pointer;
  dcl-s id int(10);
  dcl-s kp pointer;
  dcl-s kl int(10);

  if node <= 0 or node > doc.count;
    return 0;
  endif;
  pn = nodeAt(doc : node);
  if n.type <> MP_JSON_OBJECT;
    return 0;
  endif;
  id = n.first;
  dow id > 0;
    pc = nodeAt(doc : id);
    if c.keyEsc = 0;
      if c.keyLen = len;
        if len = 0 or mp_memcmp(doc.src + c.keyPos : ptr : len) = 0;
          return id;
        endif;
      endif;
    else;
      kp = unescape(doc : c.keyPos : c.keyLen : kl);
      if kl = len and (len = 0 or mp_memcmp(kp : ptr : len) = 0);
        return id;
      endif;
    endif;
    id = c.sib;
  enddo;
  return 0;
end-proc;

dcl-proc mp_json_index export;
  dcl-pi *n int(10);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
    idx  int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  dcl-ds c likeds(mp_JsonNode_t) based(pc);
  dcl-s pc pointer;
  dcl-s id int(10);
  dcl-s i  int(10);

  if node <= 0 or node > doc.count;
    return 0;
  endif;
  pn = nodeAt(doc : node);
  if (n.type <> MP_JSON_ARRAY and n.type <> MP_JSON_OBJECT)
     or idx < 1 or idx > n.count;
    return 0;
  endif;
  // sequential access (idx, idx+1, ...) continues from the cached node
  if doc.cacheArr = node and doc.cacheIdx > 0 and doc.cacheIdx <= idx;
    id = doc.cacheNode;
    i = doc.cacheIdx;
  else;
    id = n.first;
    i = 1;
  endif;
  dow i < idx and id > 0;
    pc = nodeAt(doc : id);
    id = c.sib;
    i += 1;
  enddo;
  doc.cacheArr = node;
  doc.cacheIdx = idx;
  doc.cacheNode = id;
  return id;
end-proc;

// ===========================================================================
//  Values
// ===========================================================================
dcl-proc mp_json_utf8 export;
  dcl-pi *n pointer;
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
    len  int(10);
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;

  len = 0;
  if node <= 0 or node > doc.count;
    return *null;
  endif;
  pn = nodeAt(doc : node);
  if n.type = MP_JSON_NULL;
    return *null;
  endif;
  if n.type = MP_JSON_STRING and n.valEsc = 1;
    return unescape(doc : n.valPos : n.valLen : len);
  endif;
  len = n.valLen;
  return doc.src + n.valPos;
end-proc;

dcl-proc mp_json_text export;
  dcl-pi *n varchar(MP_VALUE_MAX:4);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-s p   pointer;
  dcl-s len int(10);
  p = mp_json_utf8(doc : node : len);
  return mp_utf8ToText(p : len);
end-proc;

dcl-proc mp_json_keyText export;
  dcl-pi *n varchar(256);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-ds n likeds(mp_JsonNode_t) based(pn);
  dcl-s pn pointer;
  dcl-s p  pointer;
  dcl-s len int(10);
  if node <= 0 or node > doc.count;
    return '';
  endif;
  pn = nodeAt(doc : node);
  if n.keyEsc = 1;
    p = unescape(doc : n.keyPos : n.keyLen : len);
  else;
    p = doc.src + n.keyPos;
    len = n.keyLen;
  endif;
  return mp_utf8ToText(p : len);
end-proc;

dcl-proc mp_json_int export;
  dcl-pi *n int(20);
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
  end-pi;
  dcl-s t varchar(64);
  dcl-s ty int(10);
  ty = mp_json_type(doc : node);
  if ty <> MP_JSON_NUMBER and ty <> MP_JSON_STRING;
    return 0;
  endif;
  t = %trim(mp_json_text(doc : node));
  if t = '';
    return 0;
  endif;
  monitor;
    if %scan('e' : t) > 0 or %scan('E' : t) > 0;
      return %int(%float(t));
    endif;
    return %int(t);
  on-error;
    return 0;
  endmon;
end-proc;

dcl-proc mp_json_bool export;
  dcl-pi *n ind;
    doc  likeds(mp_JsonDoc_t);
    node int(10) value;
    dft  ind value;
  end-pi;
  dcl-s ty int(10);
  ty = mp_json_type(doc : node);
  if ty = MP_JSON_TRUE;
    return *on;
  elseif ty = MP_JSON_FALSE;
    return *off;
  endif;
  return dft;
end-proc;

// ---------------------------------------------------------------------------
//  Unescape a string span into doc.tmp (UTF-8). Returns the data pointer.
// ---------------------------------------------------------------------------
dcl-proc unescape;
  dcl-pi *n pointer;
    doc    likeds(mp_JsonDoc_t);
    pos    int(10) value;
    len    int(10) value;
    outLen int(10);
  end-pi;
  dcl-s p    pointer;
  dcl-s c    uns(3) based(p);
  dcl-s i    int(10);
  dcl-s e    int(10);
  dcl-s cp   int(10);
  dcl-s lo   int(10);

  doc.tmp.len = 0;
  mp_buf_reserve(doc.tmp : len + 4);
  i = 0;
  dow i < len;
    p = doc.src + pos + i;
    if c <> C_BSLASH;
      mp_buf_addByte(doc.tmp : c);
      i += 1;
      iter;
    endif;
    if i + 1 >= len;
      leave;
    endif;
    p += 1;
    e = c;
    i += 2;
    select;
      when e = C_QUOTE or e = C_BSLASH or e = C_SLASH;
        mp_buf_addByte(doc.tmp : e);
      when e = 98;  // b
        mp_buf_addByte(doc.tmp : 8);
      when e = 102; // f
        mp_buf_addByte(doc.tmp : 12);
      when e = 110; // n
        mp_buf_addByte(doc.tmp : 10);
      when e = 114; // r
        mp_buf_addByte(doc.tmp : 13);
      when e = 116; // t
        mp_buf_addByte(doc.tmp : 9);
      when e = 117; // u
        cp = hex4(doc : pos + i : len - i);
        i += 4;
        // surrogate pair
        if cp >= 55296 and cp <= 56319 and i + 6 <= len;
          p = doc.src + pos + i;
          if c = C_BSLASH;
            p += 1;
            if c = 117;
              lo = hex4(doc : pos + i + 2 : len - i - 2);
              if lo >= 56320 and lo <= 57343;
                cp = 65536 + (cp - 55296) * 1024 + (lo - 56320);
                i += 6;
              endif;
            endif;
          endif;
        endif;
        addCodePoint(doc.tmp : cp);
      other;
        mp_buf_addByte(doc.tmp : e);
    endsl;
  enddo;
  outLen = doc.tmp.len;
  return doc.tmp.data;
end-proc;

dcl-proc hex4;
  dcl-pi *n int(10);
    doc   likeds(mp_JsonDoc_t);
    pos   int(10) value;
    avail int(10) value;
  end-pi;
  dcl-s p pointer;
  dcl-s c uns(3) based(p);
  dcl-s i int(10);
  dcl-s v int(10) inz(0);
  dcl-s d int(10);
  if avail < 4;
    return 65533;
  endif;
  for i = 0 to 3;
    p = doc.src + pos + i;
    if c >= 48 and c <= 57;
      d = c - 48;
    elseif c >= 65 and c <= 70;
      d = c - 55;
    elseif c >= 97 and c <= 102;
      d = c - 87;
    else;
      return 65533;
    endif;
    v = v * 16 + d;
  endfor;
  return v;
end-proc;

dcl-proc addCodePoint;
  dcl-pi *n;
    buf likeds(mp_Buffer_t);
    cp  int(10) value;
  end-pi;
  if cp < 128;
    mp_buf_addByte(buf : cp);
  elseif cp < 2048;
    mp_buf_addByte(buf : 192 + %div(cp : 64));
    mp_buf_addByte(buf : 128 + %rem(cp : 64));
  elseif cp < 65536;
    mp_buf_addByte(buf : 224 + %div(cp : 4096));
    mp_buf_addByte(buf : 128 + %rem(%div(cp : 64) : 64));
    mp_buf_addByte(buf : 128 + %rem(cp : 64));
  else;
    mp_buf_addByte(buf : 240 + %div(cp : 262144));
    mp_buf_addByte(buf : 128 + %rem(%div(cp : 4096) : 64));
    mp_buf_addByte(buf : 128 + %rem(%div(cp : 64) : 64));
    mp_buf_addByte(buf : 128 + %rem(cp : 64));
  endif;
end-proc;

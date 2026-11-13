**FREE
// ===========================================================================
//  MPSQLJOB - the SQLJob "class"
//
//  An SQLJob owns one WebSocket connection to a mapepire-server and the
//  database job behind it. It creates Query objects and correlates every
//  request with its response through the request id.
// ===========================================================================
ctl-opt nomain ccsid(*char:*jobrun) alloc(*teraspace)
        option(*srcstmt:*nodebugio) bnddir('QC2LE');

/copy mpobj.rpgleinc

dcl-c WS_PATH '/db/';

dcl-pr c_memset pointer extproc('memset');
  ptr pointer value;
  chr int(10) value;
  len uns(10) value;
end-pr;

// ===========================================================================
//  Construction
// ===========================================================================
dcl-proc SQLJob_new export;
  dcl-pi *n like(MP_SQLJob_h);
    options likeds(MP_JobOptions_t) const options(*nopass);
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  dcl-s p pointer;
  dcl-ds dft likeds(MP_JobOptions_t) inz(*likeds);

  p = %alloc(%size(SQLJob_t));
  clear job;
  job.base.eye = EYE_JOB;
  job.base.status = MP_JOB_NOT_STARTED;
  job.base.uniqueIdCounter = 0;
  job.channel.trans.sd = -1;
  if %parms >= %parmnum(options);
    job.base.options = options;
  else;
    job.base.options = dft;
  endif;
  job.base.uniqueId = mp_job_nextId(p : 'sqljob');
  job.base.id = '';
  return p;
end-proc;

// ===========================================================================
//  Connection management
// ===========================================================================
dcl-proc SQLJob_connect export;
  dcl-pi *n likeds(MP_ConnectionResult_t);
    jobH   like(MP_SQLJob_h) value;
    server likeds(MP_DaemonServer_t) const;
  end-pi;
  dcl-ds job    likeds(SQLJob_t) based(p);
  dcl-s  p      pointer;
  dcl-ds result likeds(MP_ConnectionResult_t) inz;
  dcl-ds cfg    likeds(mp_TlsConfig_t) inz;
  dcl-ds creds  likeds(mp_Buffer_t) inz;
  dcl-ds b64    likeds(mp_Buffer_t) inz;
  dcl-ds pem    likeds(mp_Buffer_t) inz;
  dcl-ds w      likeds(mp_JsonWriter_t) inz;
  dcl-ds doc    likeds(mp_JsonDoc_t) inz;
  dcl-s  auth   varchar(1024);
  dcl-s  id     varchar(64);

  p = mp_job_check(jobH);
  if job.base.status <> MP_JOB_NOT_STARTED;
    mp_throw('Mapepire: SQLJob_connect: the job has already been '
             + 'connected (status ' + job.base.status + ')');
  endif;
  if server.host = '';
    mp_throw('Mapepire: SQLJob_connect: no host given');
  endif;

  // TLS settings
  cfg.useTls = server.useTls;
  cfg.ignoreUnauthorized = server.ignoreUnauthorized;
  cfg.timeoutSecs = server.timeout;
  if server.useTls and not server.ignoreUnauthorized;
    if server.ca <> '';
      mp_buf_addText(pem : server.ca);
    elseif server.caFile <> '';
      mp_readFile(server.caFile : pem);
    endif;
    if pem.len > 0;
      if not mp_pemToDer(pem.data : pem.len : cfg.pinnedDer);
        mp_buf_free(pem);
        mp_throw('Mapepire: SQLJob_connect: ca / caFile does not contain '
                 + 'a PEM certificate');
      endif;
    endif;
    mp_buf_free(pem);
  endif;

  // Authorization: Basic base64(user:password)
  mp_buf_addText(creds : server.user + ':' + server.password);
  mp_base64Encode(creds.data : creds.len : b64);
  auth = 'Basic ' + mp_utf8ToText(b64.data : b64.len);
  // do not leave the password lying around in heap storage
  if creds.len > 0;
    c_memset(creds.data : 0 : creds.len);
  endif;
  mp_buf_free(creds);
  mp_buf_free(b64);

  monitor;
    mp_ws_open(job.channel : server.host : server.port : WS_PATH
               : auth : cfg);
  on-error;
    auth = '';
    mp_buf_free(cfg.pinnedDer);
    mp_rethrow();
  endmon;
  auth = '';
  mp_buf_free(cfg.pinnedDer);

  // connect message
  id = mp_job_nextId(p : 'connect');
  mp_jw_beginObject(w);
  mp_jw_strField(w : 'id' : id);
  mp_jw_strField(w : 'type' : 'connect');
  mp_jw_strField(w : 'technique' : job.base.options.technique);
  mp_jw_strField(w : 'application' : job.base.options.application);
  if job.base.options.props <> '';
    mp_jw_strField(w : 'props' : job.base.options.props);
  endif;
  mp_jw_endObject(w);

  job.base.status = MP_JOB_READY;
  monitor;
    mp_job_request(p : w : id : doc);
  on-error;
    mp_buf_free(w.buf);
    mp_ws_close(job.channel);
    job.base.status = MP_JOB_NOT_STARTED;
    mp_rethrow();
  endmon;
  mp_buf_free(w.buf);

  result.base = mp_job_response(doc);
  result.job = mp_json_text(doc : mp_json_member(doc : 1 : 'job'));
  mp_json_free(doc);

  if not result.base.success;
    mp_ws_close(job.channel);
    job.base.status = MP_JOB_NOT_STARTED;
    mp_throwResponse(result.base : 'Mapepire: connect failed: ');
  endif;

  job.base.id = result.job;
  job.base.status = MP_JOB_READY;
  return result;
end-proc;

dcl-proc SQLJob_close export;
  dcl-pi *n;
    jobH like(MP_SQLJob_h) value;
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  dcl-s  p   pointer;
  dcl-ds w   likeds(mp_JsonWriter_t) inz;
  dcl-ds doc likeds(mp_JsonDoc_t) inz;
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-s  pq  pointer;
  dcl-s  id  varchar(64);

  p = mp_job_check(jobH);
  if job.channel.isOpen;
    // tell the server we are leaving; ignore any problem doing so
    monitor;
      id = mp_job_nextId(p : 'exit');
      mp_jw_beginObject(w);
      mp_jw_strField(w : 'id' : id);
      mp_jw_strField(w : 'type' : 'exit');
      mp_jw_endObject(w);
      mp_job_request(p : w : id : doc);
    on-error;
    endmon;
    mp_buf_free(w.buf);
    mp_json_free(doc);
    mp_ws_close(job.channel);
  endif;
  job.base.status = MP_JOB_ENDED;

  // the server freed every cursor along with the connection
  pq = job.firstQuery;
  dow pq <> *null;
    q.serverOpen = *off;
    if q.state <> MP_QUERY_ERROR;
      q.state = MP_QUERY_RUN_DONE;
    endif;
    pq = q.nxt;
  enddo;
end-proc;

dcl-proc SQLJob_free export;
  dcl-pi *n;
    jobH like(MP_SQLJob_h);
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  dcl-s  p   pointer;
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-s  pq  pointer;
  dcl-s  nxt pointer;

  if jobH = *null;
    return;
  endif;
  p = mp_job_check(jobH);
  SQLJob_close(p);
  pq = job.firstQuery;
  dow pq <> *null;
    nxt = q.nxt;
    mp_query_destroy(pq);
    pq = nxt;
  enddo;
  job.base.eye = EYE_FREED;
  dealloc p;
  jobH = *null;
end-proc;

// ===========================================================================
//  Status / identity
// ===========================================================================
dcl-proc SQLJob_getStatus export;
  dcl-pi *n varchar(10);
    jobH like(MP_SQLJob_h) value;
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  dcl-s  p   pointer;
  p = mp_job_check(jobH);
  return job.base.status;
end-proc;

dcl-proc SQLJob_getId export;
  dcl-pi *n varchar(64);
    jobH like(MP_SQLJob_h) value;
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  dcl-s  p   pointer;
  p = mp_job_check(jobH);
  return job.base.id;
end-proc;

dcl-proc SQLJob_getUniqueId export;
  dcl-pi *n varchar(64);
    jobH   like(MP_SQLJob_h) value;
    prefix varchar(32) const options(*nopass);
  end-pi;
  if %parms >= %parmnum(prefix);
    return mp_job_nextId(mp_job_check(jobH) : prefix);
  endif;
  return mp_job_nextId(mp_job_check(jobH) : 'id');
end-proc;

// ===========================================================================
//  Queries
// ===========================================================================
dcl-proc SQLJob_query export;
  dcl-pi *n like(MP_Query_h);
    jobH like(MP_SQLJob_h) value;
    sql  varchar(MP_SQL_MAX:4) const;
    opts likeds(MP_QueryOptions_t) const options(*nopass);
  end-pi;
  dcl-ds dft likeds(MP_QueryOptions_t) inz(*likeds);
  if %parms >= %parmnum(opts);
    return mp_query_create(mp_job_check(jobH) : sql : opts);
  endif;
  return mp_query_create(mp_job_check(jobH) : sql : dft);
end-proc;

dcl-proc SQLJob_queryAndRun export;
  dcl-pi *n like(MP_QueryResult_h);
    jobH        like(MP_SQLJob_h) value;
    sql         varchar(MP_SQL_MAX:4) const;
    opts        likeds(MP_QueryOptions_t) const options(*nopass:*omit);
    rowsToFetch int(10) value options(*nopass);
  end-pi;
  dcl-ds dft likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-s  pq  pointer;
  dcl-s  res pointer;

  if %parms >= %parmnum(opts) and %addr(opts) <> *null;
    pq = mp_query_create(mp_job_check(jobH) : sql : opts);
  else;
    pq = mp_query_create(mp_job_check(jobH) : sql : dft);
  endif;

  monitor;
    if %parms >= %parmnum(rowsToFetch);
      res = Query_run(pq : rowsToFetch);
    else;
      res = Query_run(pq);
    endif;
    // like the reference implementation: run, then close the query
    Query_close(pq);
  on-error;
    Query_free(pq);
    mp_rethrow();
  endmon;
  q.freeWithResult = *on;
  return res;
end-proc;

dcl-proc SQLJob_explain export;
  dcl-pi *n like(MP_QueryResult_h);
    jobH  like(MP_SQLJob_h) value;
    sql   varchar(MP_SQL_MAX:4) const;
    runIt ind value options(*nopass);
  end-pi;
  dcl-ds dft likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-s  pq  pointer;
  dcl-s  res pointer;

  pq = mp_query_create(mp_job_check(jobH) : sql : dft);
  q.isExplain = *on;
  q.explainRun = *off;
  if %parms >= %parmnum(runIt);
    q.explainRun = runIt;
  endif;
  monitor;
    res = mp_query_explain(pq);
  on-error;
    Query_free(pq);
    mp_rethrow();
  endmon;
  q.freeWithResult = *on;
  return res;
end-proc;

// ===========================================================================
//  Server information
// ===========================================================================
dcl-proc SQLJob_ping export;
  dcl-pi *n likeds(MP_PingResult_t);
    jobH like(MP_SQLJob_h) value;
  end-pi;
  dcl-ds result likeds(MP_PingResult_t) inz;
  dcl-ds doc    likeds(mp_JsonDoc_t) inz;
  simpleRequest(mp_job_check(jobH) : 'ping' : doc);
  result.base = mp_job_response(doc);
  result.alive = mp_json_bool(doc : mp_json_member(doc : 1 : 'alive') : *off);
  result.dbAlive = mp_json_bool(doc : mp_json_member(doc : 1 : 'db_alive')
                                : *off);
  mp_json_free(doc);
  return result;
end-proc;

dcl-proc SQLJob_getVersion export;
  dcl-pi *n likeds(MP_VersionResult_t);
    jobH like(MP_SQLJob_h) value;
  end-pi;
  dcl-ds result likeds(MP_VersionResult_t) inz;
  dcl-ds doc    likeds(mp_JsonDoc_t) inz;
  simpleRequest(mp_job_check(jobH) : 'getversion' : doc);
  result.base = mp_job_response(doc);
  result.version = mp_json_text(doc : mp_json_member(doc : 1 : 'version'));
  result.buildDate = mp_json_text(doc
                                  : mp_json_member(doc : 1 : 'build_date'));
  mp_json_free(doc);
  if not result.base.success;
    mp_throwResponse(result.base : 'Mapepire: getversion failed: ');
  endif;
  return result;
end-proc;

dcl-proc SQLJob_getDbJob export;
  dcl-pi *n varchar(64);
    jobH like(MP_SQLJob_h) value;
  end-pi;
  dcl-ds resp likeds(MP_ServerResponse_t);
  dcl-ds doc  likeds(mp_JsonDoc_t) inz;
  dcl-s  name varchar(64);
  simpleRequest(mp_job_check(jobH) : 'getdbjob' : doc);
  resp = mp_job_response(doc);
  name = mp_json_text(doc : mp_json_member(doc : 1 : 'job'));
  mp_json_free(doc);
  if not resp.success;
    mp_throwResponse(resp : 'Mapepire: getdbjob failed: ');
  endif;
  return name;
end-proc;

// {"id":..,"type":<type>}
dcl-proc simpleRequest;
  dcl-pi *n;
    p    pointer value;
    type varchar(32) const;
    doc  likeds(mp_JsonDoc_t);
  end-pi;
  dcl-ds w  likeds(mp_JsonWriter_t) inz;
  dcl-s  id varchar(64);
  id = mp_job_nextId(p : type);
  mp_jw_beginObject(w);
  mp_jw_strField(w : 'id' : id);
  mp_jw_strField(w : 'type' : type);
  mp_jw_endObject(w);
  monitor;
    mp_job_request(p : w : id : doc);
  on-error;
    mp_buf_free(w.buf);
    mp_rethrow();
  endmon;
  mp_buf_free(w.buf);
end-proc;

// ===========================================================================
//  Internal services used by MPQUERY
// ===========================================================================
dcl-proc mp_job_check export;
  dcl-pi *n pointer;
    p pointer value;
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  if p = *null;
    mp_throw('Mapepire: SQLJob handle is *NULL');
  endif;
  if job.base.eye <> EYE_JOB;
    mp_throw('Mapepire: not a valid SQLJob handle');
  endif;
  return p;
end-proc;

dcl-proc mp_job_isConnected export;
  dcl-pi *n ind;
    p pointer value;
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  return job.channel.isOpen;
end-proc;

dcl-proc mp_job_nextId export;
  dcl-pi *n varchar(64);
    p      pointer value;
    prefix varchar(32) const;
  end-pi;
  dcl-ds job likeds(SQLJob_t) based(p);
  job.base.uniqueIdCounter += 1;
  return prefix + %char(job.base.uniqueIdCounter);
end-proc;

dcl-proc mp_job_request export;
  dcl-pi *n;
    p   pointer value;
    w   likeds(mp_JsonWriter_t);
    id  varchar(64) const;
    doc likeds(mp_JsonDoc_t);
  end-pi;
  dcl-ds job   likeds(SQLJob_t) based(p);
  dcl-s  found ind inz(*off);

  if not job.channel.isOpen;
    mp_throw('Mapepire: the SQLJob is not connected (status '
             + job.base.status + ')');
  endif;

  job.base.status = MP_JOB_BUSY;
  monitor;
    mp_ws_sendText(job.channel : w.buf.data : w.buf.len);
    dow not found;
      mp_ws_receive(job.channel);
      mp_json_parse(doc : job.channel.msg);
      if mp_json_text(doc : mp_json_member(doc : 1 : 'id')) = id;
        found = *on;
      else;
        // a response to something else (should not happen with the
        // synchronous API) - skip it
        mp_json_free(doc);
      endif;
    enddo;
  on-error;
    if job.channel.isOpen;
      job.base.status = MP_JOB_READY;
    else;
      job.base.status = MP_JOB_ENDED;
    endif;
    mp_rethrow();
  endmon;
  job.base.status = MP_JOB_READY;
end-proc;

dcl-proc mp_job_response export;
  dcl-pi *n likeds(MP_ServerResponse_t);
    doc likeds(mp_JsonDoc_t);
  end-pi;
  dcl-ds r likeds(MP_ServerResponse_t) inz;
  r.id = mp_json_text(doc : mp_json_member(doc : 1 : 'id'));
  r.success = mp_json_bool(doc : mp_json_member(doc : 1 : 'success') : *off);
  r.executionTime = mp_json_int(doc
                                : mp_json_member(doc : 1 : 'execution_time'));
  r.error = mp_json_text(doc : mp_json_member(doc : 1 : 'error'));
  r.sqlRc = mp_json_int(doc : mp_json_member(doc : 1 : 'sql_rc'));
  r.sqlState = mp_json_text(doc : mp_json_member(doc : 1 : 'sql_state'));
  return r;
end-proc;

dcl-proc mp_job_linkQuery export;
  dcl-pi *n;
    p  pointer value;
    pq pointer value;
  end-pi;
  dcl-ds job  likeds(SQLJob_t) based(p);
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-ds last likeds(Query_t) based(pl);
  dcl-s  pl   pointer;
  q.prev = job.lastQuery;
  q.nxt = *null;
  if job.lastQuery <> *null;
    pl = job.lastQuery;
    last.nxt = pq;
  else;
    job.firstQuery = pq;
  endif;
  job.lastQuery = pq;
end-proc;

dcl-proc mp_job_unlinkQuery export;
  dcl-pi *n;
    p  pointer value;
    pq pointer value;
  end-pi;
  dcl-ds job  likeds(SQLJob_t) based(p);
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-ds o    likeds(Query_t) based(po);
  dcl-s  po   pointer;
  if q.prev <> *null;
    po = q.prev;
    o.nxt = q.nxt;
  else;
    job.firstQuery = q.nxt;
  endif;
  if q.nxt <> *null;
    po = q.nxt;
    o.prev = q.prev;
  else;
    job.lastQuery = q.prev;
  endif;
  q.prev = *null;
  q.nxt = *null;
end-proc;

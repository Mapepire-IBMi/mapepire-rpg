**FREE
// ===========================================================================
//  MPQUERY - the Query, QueryResult and Params "classes"
//
//  Query state machine (reference architecture):
//
//     NOT_YET_RUN --run--> RUN_MORE_DATA_AVAIL --fetchMore--> RUN_DONE
//          |                   |  (is_done = false)    (is_done = true)
//          |                   +--close--> RUN_DONE
//          +---- any failure --> ERROR
// ===========================================================================
ctl-opt nomain ccsid(*char:*jobrun) alloc(*teraspace)
        option(*srcstmt:*nodebugio) bnddir('QC2LE');

/copy mpobj.rpgleinc

dcl-c DEFAULT_ROWS 100;
dcl-c COLUMN_SIZE  %size(MP_ColumnMetaData_t);

// ===========================================================================
//  Query construction / destruction
// ===========================================================================
dcl-proc mp_query_create export;
  dcl-pi *n pointer;
    pJob pointer value;
    sql  varchar(MP_SQL_MAX:4) const;
    opts likeds(MP_QueryOptions_t) const;
  end-pi;
  dcl-ds q likeds(Query_t) based(pq);
  dcl-s  pq pointer;

  pq = %alloc(%size(Query_t));
  clear q;
  q.eye = EYE_QUERY;
  q.job = pJob;
  mp_buf_addText(q.sql : sql);
  q.isClCommand = opts.isClCommand;
  q.shouldAutoClose = opts.autoClose;
  q.isTerseResults = opts.isTerseResults;
  q.isPrepared = opts.parameters <> *null;
  if q.isPrepared;
    mp_params_toJson(opts.parameters : q.parameters);
  endif;
  q.rowsToFetch = DEFAULT_ROWS;
  q.state = MP_QUERY_NOT_YET_RUN;
  q.correlationId = '';
  mp_job_linkQuery(pJob : pq);
  return pq;
end-proc;

dcl-proc mp_query_destroy export;
  dcl-pi *n;
    pq pointer value;
  end-pi;
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-ds r   likeds(QueryResult_t) based(pr);
  dcl-s  pr  pointer;
  dcl-s  nxt pointer;

  pr = q.firstResult;
  dow pr <> *null;
    nxt = r.nxt;
    destroyResult(pr);
    pr = nxt;
  enddo;
  q.firstResult = *null;
  q.lastResult = *null;
  if q.job <> *null;
    mp_job_unlinkQuery(q.job : pq);
  endif;
  mp_buf_free(q.sql);
  mp_buf_free(q.parameters);
  if q.columns <> *null;
    dealloc q.columns;
  endif;
  q.eye = EYE_FREED;
  dealloc pq;
end-proc;

dcl-proc checkQuery;
  dcl-pi *n pointer;
    pq pointer value;
  end-pi;
  dcl-ds q likeds(Query_t) based(pq);
  if pq = *null;
    mp_throw('Mapepire: Query handle is *NULL');
  endif;
  if q.eye <> EYE_QUERY;
    mp_throw('Mapepire: not a valid Query handle');
  endif;
  return pq;
end-proc;

// ===========================================================================
//  Query execution
// ===========================================================================
dcl-proc Query_run export;
  dcl-pi *n like(MP_QueryResult_h);
    queryH      like(MP_Query_h) value;
    rowsToFetch int(10) value options(*nopass);
  end-pi;
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-s  pq   pointer;
  dcl-ds w    likeds(mp_JsonWriter_t) inz;
  dcl-s  id   varchar(64);
  dcl-s  rows int(10);

  pq = checkQuery(queryH);
  select;
    when q.state = MP_QUERY_RUN_MORE_DATA_AVAIL;
      mp_throw('Mapepire: Query_run: statement has already been run');
    when q.state = MP_QUERY_RUN_DONE;
      mp_throw('Mapepire: Query_run: statement has already been fully run');
  endsl;

  rows = q.rowsToFetch;
  if %parms >= %parmnum(rowsToFetch);
    if rowsToFetch > 0;
      rows = rowsToFetch;
      q.rowsToFetch = rowsToFetch;
    endif;
  endif;

  mp_jw_beginObject(w);
  if q.isClCommand;
    id = mp_job_nextId(q.job : 'clcommand');
    mp_jw_strField(w : 'id' : id);
    mp_jw_strField(w : 'type' : 'cl');
    mp_jw_boolField(w : 'terse' : q.isTerseResults);
    mp_jw_key(w : 'cmd');
    mp_jw_stringUtf8(w : q.sql.data : q.sql.len);
  else;
    id = mp_job_nextId(q.job : 'query');
    mp_jw_strField(w : 'id' : id);
    if q.isPrepared;
      mp_jw_strField(w : 'type' : 'prepare_sql_execute');
    else;
      mp_jw_strField(w : 'type' : 'sql');
    endif;
    mp_jw_key(w : 'sql');
    mp_jw_stringUtf8(w : q.sql.data : q.sql.len);
    mp_jw_boolField(w : 'terse' : q.isTerseResults);
    mp_jw_intField(w : 'rows' : rows);
    if q.isPrepared;
      mp_jw_key(w : 'parameters');
      mp_jw_rawUtf8(w : q.parameters.data : q.parameters.len);
    endif;
  endif;
  mp_jw_endObject(w);

  return execute(pq : w : id : *on);
end-proc;

dcl-proc Query_fetchMore export;
  dcl-pi *n like(MP_QueryResult_h);
    queryH      like(MP_Query_h) value;
    rowsToFetch int(10) value options(*nopass);
  end-pi;
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-s  pq   pointer;
  dcl-ds w    likeds(mp_JsonWriter_t) inz;
  dcl-s  id   varchar(64);
  dcl-s  rows int(10);

  pq = checkQuery(queryH);
  select;
    when q.state = MP_QUERY_NOT_YET_RUN;
      mp_throw('Mapepire: Query_fetchMore: statement has not been run yet');
    when q.state = MP_QUERY_RUN_DONE;
      mp_throw('Mapepire: Query_fetchMore: statement has already been '
               + 'fully run');
    when q.state = MP_QUERY_ERROR;
      mp_throw('Mapepire: Query_fetchMore: statement ended in error');
  endsl;

  rows = q.rowsToFetch;
  if %parms >= %parmnum(rowsToFetch);
    if rowsToFetch > 0;
      rows = rowsToFetch;
      q.rowsToFetch = rowsToFetch;
    endif;
  endif;

  id = mp_job_nextId(q.job : 'fetchMore');
  mp_jw_beginObject(w);
  mp_jw_strField(w : 'id' : id);
  mp_jw_strField(w : 'cont_id' : q.correlationId);
  mp_jw_strField(w : 'type' : 'sqlmore');
  mp_jw_intField(w : 'rows' : rows);
  mp_jw_endObject(w);

  return execute(pq : w : id : *off);
end-proc;

dcl-proc Query_execute export;
  dcl-pi *n like(MP_QueryResult_h);
    queryH      like(MP_Query_h) value;
    parameters  like(MP_Params_h) value;
    rowsToFetch int(10) value options(*nopass);
  end-pi;
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-s  pq   pointer;
  dcl-ds w    likeds(mp_JsonWriter_t) inz;
  dcl-ds parm likeds(mp_Buffer_t) inz;
  dcl-s  id   varchar(64);
  dcl-s  rows int(10);

  pq = checkQuery(queryH);
  if not q.isPrepared or q.correlationId = '' or not q.serverOpen;
    mp_throw('Mapepire: Query_execute: the query is not an open prepared '
             + 'statement (run it with parameters first)');
  endif;

  rows = q.rowsToFetch;
  if %parms >= %parmnum(rowsToFetch);
    if rowsToFetch > 0;
      rows = rowsToFetch;
    endif;
  endif;

  mp_params_toJson(parameters : parm);
  id = mp_job_nextId(q.job : 'execute');
  mp_jw_beginObject(w);
  mp_jw_strField(w : 'id' : id);
  mp_jw_strField(w : 'type' : 'execute');
  mp_jw_strField(w : 'cont_id' : q.correlationId);
  mp_jw_key(w : 'parameters');
  mp_jw_rawUtf8(w : parm.data : parm.len);
  mp_jw_intField(w : 'rows' : rows);
  mp_jw_boolField(w : 'terse' : q.isTerseResults);
  mp_jw_endObject(w);
  mp_buf_free(parm);

  // the prepared statement's cursor gets new rows
  q.state = MP_QUERY_RUN_MORE_DATA_AVAIL;
  return execute(pq : w : id : *off);
end-proc;

dcl-proc mp_query_explain export;
  dcl-pi *n pointer;
    pq pointer value;
  end-pi;
  dcl-ds q  likeds(Query_t) based(pq);
  dcl-ds w  likeds(mp_JsonWriter_t) inz;
  dcl-s  id varchar(64);

  id = mp_job_nextId(q.job : 'explain');
  mp_jw_beginObject(w);
  mp_jw_strField(w : 'id' : id);
  mp_jw_strField(w : 'type' : 'dove');
  mp_jw_key(w : 'sql');
  mp_jw_stringUtf8(w : q.sql.data : q.sql.len);
  mp_jw_boolField(w : 'run' : q.explainRun);
  mp_jw_endObject(w);
  return execute(pq : w : id : *on);
end-proc;

// ---------------------------------------------------------------------------
//  Send a request for the query and turn the response into a result
// ---------------------------------------------------------------------------
dcl-proc execute;
  dcl-pi *n pointer;
    pq      pointer value;
    w       likeds(mp_JsonWriter_t);
    id      varchar(64) const;
    opening ind value;
  end-pi;
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-ds doc likeds(mp_JsonDoc_t) inz;
  dcl-ds r   likeds(QueryResult_t) based(pr);
  dcl-s  pr  pointer;
  dcl-ds err likeds(MP_ServerResponse_t);

  monitor;
    mp_job_request(q.job : w : id : doc);
  on-error;
    mp_buf_free(w.buf);
    q.state = MP_QUERY_ERROR;
    mp_rethrow();
  endmon;
  mp_buf_free(w.buf);

  pr = createResult(pq : doc);

  if not r.summary.base.success and not q.isClCommand;
    q.state = MP_QUERY_ERROR;
    err = r.summary.base;
    destroyResult(pr);
    mp_throwResponse(err);
  endif;

  if opening;
    q.correlationId = id;
    q.serverOpen = r.summary.base.success
                   and (r.summary.hasResults or q.isPrepared);
  endif;

  if r.summary.isDone;
    q.state = MP_QUERY_RUN_DONE;
  else;
    q.state = MP_QUERY_RUN_MORE_DATA_AVAIL;
  endif;

  if r.summary.isDone and q.shouldAutoClose;
    Query_close(pq);
  endif;
  return pr;
end-proc;

dcl-proc Query_close export;
  dcl-pi *n;
    queryH like(MP_Query_h) value;
  end-pi;
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-s  pq  pointer;
  dcl-ds w   likeds(mp_JsonWriter_t) inz;
  dcl-ds doc likeds(mp_JsonDoc_t) inz;
  dcl-s  id  varchar(64);

  pq = checkQuery(queryH);
  if q.state <> MP_QUERY_ERROR;
    q.state = MP_QUERY_RUN_DONE;
  endif;
  if not q.serverOpen or q.correlationId = '';
    return;
  endif;
  q.serverOpen = *off;
  if not mp_job_isConnected(q.job);
    return;
  endif;

  id = mp_job_nextId(q.job : 'sqlclose');
  mp_jw_beginObject(w);
  mp_jw_strField(w : 'id' : id);
  mp_jw_strField(w : 'cont_id' : q.correlationId);
  mp_jw_strField(w : 'type' : 'sqlclose');
  mp_jw_endObject(w);
  // the cursor may already be gone on the server; that is fine
  monitor;
    mp_job_request(q.job : w : id : doc);
  on-error;
  endmon;
  mp_buf_free(w.buf);
  mp_json_free(doc);
end-proc;

dcl-proc Query_getState export;
  dcl-pi *n int(10);
    queryH like(MP_Query_h) value;
  end-pi;
  dcl-ds q  likeds(Query_t) based(pq);
  dcl-s  pq pointer;
  pq = checkQuery(queryH);
  return q.state;
end-proc;

dcl-proc Query_getId export;
  dcl-pi *n varchar(64);
    queryH like(MP_Query_h) value;
  end-pi;
  dcl-ds q  likeds(Query_t) based(pq);
  dcl-s  pq pointer;
  pq = checkQuery(queryH);
  return q.correlationId;
end-proc;

dcl-proc Query_free export;
  dcl-pi *n;
    queryH like(MP_Query_h);
  end-pi;
  dcl-s pq pointer;
  if queryH = *null;
    return;
  endif;
  pq = checkQuery(queryH);
  monitor;
    Query_close(pq);
  on-error;
  endmon;
  mp_query_destroy(pq);
  queryH = *null;
end-proc;

// ===========================================================================
//  QueryResult
// ===========================================================================
dcl-proc createResult;
  dcl-pi *n pointer;
    pq  pointer value;
    doc likeds(mp_JsonDoc_t);
  end-pi;
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-ds r    likeds(QueryResult_t) based(pr);
  dcl-s  pr   pointer;
  dcl-ds last likeds(QueryResult_t) based(pl);
  dcl-s  pl   pointer;
  dcl-s  meta int(10);
  dcl-s  node int(10);
  dcl-s  i    int(10);
  dcl-s  pRow pointer;
  dcl-s  rowNode int(10) based(pRow);
  dcl-s  dataKey varchar(16);
  dcl-s  metaKey varchar(16);

  pr = %alloc(%size(QueryResult_t));
  clear r;
  r.eye = EYE_RESULT;
  r.query = pq;
  // take over the parsed document
  r.doc = doc;
  clear doc;

  if q.isExplain;
    dataKey = 'vedata';
    metaKey = 'vemetadata';
  else;
    dataKey = 'data';
    metaKey = 'metadata';
  endif;

  r.summary.base = mp_job_response(r.doc);
  r.summary.hasResults = mp_json_bool(r.doc
                         : mp_json_member(r.doc : 1 : 'has_results') : *off);
  // missing is_done means there is nothing more to fetch
  r.summary.isDone = mp_json_bool(r.doc
                     : mp_json_member(r.doc : 1 : 'is_done') : *on);
  r.summary.updateCount = mp_json_int(r.doc
                          : mp_json_member(r.doc : 1 : 'update_count'));
  r.summary.parameterCount = mp_json_int(r.doc
                             : mp_json_member(r.doc : 1 : 'parameter_count'));

  meta = mp_json_member(r.doc : 1 : metaKey);
  if mp_json_type(r.doc : meta) = MP_JSON_OBJECT;
    storeColumns(pq : r.doc : meta);
  endif;
  r.summary.columnCount = q.columnCount;

  r.dataNode = mp_json_member(r.doc : 1 : dataKey);
  if mp_json_type(r.doc : r.dataNode) = MP_JSON_ARRAY;
    r.summary.rowCount = mp_json_count(r.doc : r.dataNode);
  else;
    r.dataNode = 0;
    r.summary.rowCount = 0;
  endif;
  if r.summary.rowCount > 0;
    r.rowNodes = %alloc(r.summary.rowCount * 4);
    node = mp_json_first(r.doc : r.dataNode);
    for i = 1 to r.summary.rowCount;
      pRow = r.rowNodes + (i - 1) * 4;
      rowNode = node;
      node = mp_json_next(r.doc : node);
    endfor;
  endif;

  // link into the query's result list
  r.prev = q.lastResult;
  if q.lastResult <> *null;
    pl = q.lastResult;
    last.nxt = pr;
  else;
    q.firstResult = pr;
  endif;
  q.lastResult = pr;
  return pr;
end-proc;

// Copy the column metadata into the query (shared by all of its results)
dcl-proc storeColumns;
  dcl-pi *n;
    pq   pointer value;
    doc  likeds(mp_JsonDoc_t);
    meta int(10) value;
  end-pi;
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-ds col  likeds(MP_ColumnMetaData_t) based(pc);
  dcl-s  pc   pointer;
  dcl-s  cols int(10);
  dcl-s  n    int(10);
  dcl-s  node int(10);
  dcl-s  i    int(10);

  cols = mp_json_member(doc : meta : 'columns');
  if mp_json_type(doc : cols) <> MP_JSON_ARRAY;
    return;
  endif;
  n = mp_json_count(doc : cols);
  if q.columns <> *null;
    dealloc q.columns;
    q.columns = *null;
  endif;
  q.columnCount = n;
  if n = 0;
    return;
  endif;
  q.columns = %alloc(n * COLUMN_SIZE);
  node = mp_json_first(doc : cols);
  for i = 1 to n;
    pc = q.columns + (i - 1) * COLUMN_SIZE;
    clear col;
    col.name = mp_json_text(doc : mp_json_member(doc : node : 'name'));
    col.label = mp_json_text(doc : mp_json_member(doc : node : 'label'));
    col.type = mp_json_text(doc : mp_json_member(doc : node : 'type'));
    col.displaySize = mp_json_int(doc
                      : mp_json_member(doc : node : 'display_size'));
    col.precision = mp_json_int(doc : mp_json_member(doc : node : 'precision'));
    col.scale = mp_json_int(doc : mp_json_member(doc : node : 'scale'));
    if mp_json_member(doc : node : 'nullable') > 0;
      col.nullable = mp_json_int(doc : mp_json_member(doc : node : 'nullable'));
    else;
      col.nullable = 2;
    endif;
    col.autoIncrement = mp_json_bool(doc
                        : mp_json_member(doc : node : 'autoIncrement') : *off);
    col.readOnly = mp_json_bool(doc
                   : mp_json_member(doc : node : 'readOnly') : *off);
    col.writeable = mp_json_bool(doc
                    : mp_json_member(doc : node : 'writeable') : *off);
    col.table = mp_json_text(doc : mp_json_member(doc : node : 'table'));
    node = mp_json_next(doc : node);
  endfor;
end-proc;

dcl-proc destroyResult;
  dcl-pi *n;
    pr pointer value;
  end-pi;
  dcl-ds r likeds(QueryResult_t) based(pr);
  dcl-ds q likeds(Query_t) based(pq);
  dcl-s  pq pointer;
  dcl-ds o likeds(QueryResult_t) based(po);
  dcl-s  po pointer;

  pq = r.query;
  if pq <> *null;
    if r.prev <> *null;
      po = r.prev;
      o.nxt = r.nxt;
    else;
      q.firstResult = r.nxt;
    endif;
    if r.nxt <> *null;
      po = r.nxt;
      o.prev = r.prev;
    else;
      q.lastResult = r.prev;
    endif;
  endif;
  mp_json_free(r.doc);
  if r.rowNodes <> *null;
    dealloc r.rowNodes;
  endif;
  r.eye = EYE_FREED;
  dealloc pr;
end-proc;

dcl-proc checkResult;
  dcl-pi *n pointer;
    pr pointer value;
  end-pi;
  dcl-ds r likeds(QueryResult_t) based(pr);
  if pr = *null;
    mp_throw('Mapepire: QueryResult handle is *NULL');
  endif;
  if r.eye <> EYE_RESULT;
    mp_throw('Mapepire: not a valid QueryResult handle');
  endif;
  return pr;
end-proc;

dcl-proc QueryResult_free export;
  dcl-pi *n;
    resultH like(MP_QueryResult_h);
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  dcl-ds q  likeds(Query_t) based(pq);
  dcl-s  pq pointer;

  if resultH = *null;
    return;
  endif;
  pr = checkResult(resultH);
  pq = r.query;
  destroyResult(pr);
  resultH = *null;
  // a query created by queryAndRun / explain goes with its last result
  if pq <> *null;
    if q.freeWithResult and q.firstResult = *null;
      Query_free(pq);
    endif;
  endif;
end-proc;

dcl-proc QueryResult_get export;
  dcl-pi *n likeds(MP_QueryResult_t);
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return r.summary;
end-proc;

dcl-proc QueryResult_isSuccess export;
  dcl-pi *n ind;
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return r.summary.base.success;
end-proc;

dcl-proc QueryResult_isDone export;
  dcl-pi *n ind;
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return r.summary.isDone;
end-proc;

dcl-proc QueryResult_getRowCount export;
  dcl-pi *n int(10);
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return r.summary.rowCount;
end-proc;

dcl-proc QueryResult_getColumnCount export;
  dcl-pi *n int(10);
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return r.summary.columnCount;
end-proc;

dcl-proc QueryResult_getUpdateCount export;
  dcl-pi *n int(20);
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return r.summary.updateCount;
end-proc;

dcl-proc QueryResult_getColumn export;
  dcl-pi *n likeds(MP_ColumnMetaData_t);
    resultH like(MP_QueryResult_h) value;
    column  int(10) value;
  end-pi;
  dcl-ds r   likeds(QueryResult_t) based(pr);
  dcl-s  pr  pointer;
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-s  pq  pointer;
  dcl-ds col likeds(MP_ColumnMetaData_t) based(pc);
  dcl-s  pc  pointer;

  pr = checkResult(resultH);
  pq = r.query;
  if column < 1 or column > q.columnCount;
    mp_throw('Mapepire: column ' + %char(column) + ' does not exist');
  endif;
  pc = q.columns + (column - 1) * COLUMN_SIZE;
  return col;
end-proc;

dcl-proc QueryResult_getColumnIndex export;
  dcl-pi *n int(10);
    resultH like(MP_QueryResult_h) value;
    name    varchar(128) const;
  end-pi;
  dcl-ds r   likeds(QueryResult_t) based(pr);
  dcl-s  pr  pointer;
  dcl-s  pq  pointer;
  pr = checkResult(resultH);
  pq = r.query;
  return columnIndex(pq : name);
end-proc;

dcl-proc columnIndex;
  dcl-pi *n int(10);
    pq   pointer value;
    name varchar(128) const;
  end-pi;
  dcl-c LOWER 'abcdefghijklmnopqrstuvwxyz';
  dcl-c UPPER 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  dcl-ds q   likeds(Query_t) based(pq);
  dcl-ds col likeds(MP_ColumnMetaData_t) based(pc);
  dcl-s  pc  pointer;
  dcl-s  i   int(10);
  dcl-s  up  varchar(128);

  for i = 1 to q.columnCount;
    pc = q.columns + (i - 1) * COLUMN_SIZE;
    if col.name = name;
      return i;
    endif;
  endfor;
  up = %xlate(LOWER : UPPER : name);
  for i = 1 to q.columnCount;
    pc = q.columns + (i - 1) * COLUMN_SIZE;
    if %xlate(LOWER : UPPER : col.name) = up;
      return i;
    endif;
  endfor;
  return 0;
end-proc;

// JSON node of a cell (0 = no such cell)
dcl-proc cellNode;
  dcl-pi *n int(10);
    pr     pointer value;
    row    int(10) value;
    column int(10) value;
  end-pi;
  dcl-ds r    likeds(QueryResult_t) based(pr);
  dcl-ds q    likeds(Query_t) based(pq);
  dcl-s  pq   pointer;
  dcl-ds col  likeds(MP_ColumnMetaData_t) based(pc);
  dcl-s  pc   pointer;
  dcl-s  pRow pointer;
  dcl-s  rowNode int(10) based(pRow);
  dcl-s  node int(10);

  if row < 1 or row > r.summary.rowCount;
    mp_throw('Mapepire: row ' + %char(row) + ' does not exist (rows: '
             + %char(r.summary.rowCount) + ')');
  endif;
  pRow = r.rowNodes + (row - 1) * 4;
  node = rowNode;
  if mp_json_type(r.doc : node) = MP_JSON_OBJECT;
    // object rows: look the column up by name (column names can repeat in
    // the metadata while object keys cannot, so position is not reliable)
    pq = r.query;
    if column >= 1 and column <= q.columnCount;
      pc = q.columns + (column - 1) * COLUMN_SIZE;
      return mp_json_member(r.doc : node : col.name);
    endif;
  endif;
  return mp_json_index(r.doc : node : column);
end-proc;

dcl-proc QueryResult_getValue export;
  dcl-pi *n varchar(MP_VALUE_MAX:4);
    resultH like(MP_QueryResult_h) value;
    row     int(10) value;
    column  int(10) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return mp_json_text(r.doc : cellNode(pr : row : column));
end-proc;

dcl-proc QueryResult_getValueByName export;
  dcl-pi *n varchar(MP_VALUE_MAX:4);
    resultH like(MP_QueryResult_h) value;
    row     int(10) value;
    name    varchar(128) const;
  end-pi;
  dcl-ds r    likeds(QueryResult_t) based(pr);
  dcl-s  pr   pointer;
  dcl-s  pRow pointer;
  dcl-s  rowNode int(10) based(pRow);
  dcl-s  idx  int(10);
  dcl-s  node int(10);

  pr = checkResult(resultH);
  if row < 1 or row > r.summary.rowCount;
    mp_throw('Mapepire: row ' + %char(row) + ' does not exist (rows: '
             + %char(r.summary.rowCount) + ')');
  endif;
  pRow = r.rowNodes + (row - 1) * 4;
  if mp_json_type(r.doc : rowNode) = MP_JSON_OBJECT;
    node = mp_json_member(r.doc : rowNode : name);
    if node = 0;
      idx = columnIndex(r.query : name);
      if idx > 0;
        node = cellNode(pr : row : idx);
      endif;
    endif;
  else;
    idx = columnIndex(r.query : name);
    if idx = 0;
      mp_throw('Mapepire: column ' + name + ' does not exist');
    endif;
    node = cellNode(pr : row : idx);
  endif;
  return mp_json_text(r.doc : node);
end-proc;

dcl-proc QueryResult_isNull export;
  dcl-pi *n ind;
    resultH like(MP_QueryResult_h) value;
    row     int(10) value;
    column  int(10) value;
  end-pi;
  dcl-ds r    likeds(QueryResult_t) based(pr);
  dcl-s  pr   pointer;
  dcl-s  node int(10);
  pr = checkResult(resultH);
  node = cellNode(pr : row : column);
  return node = 0 or mp_json_type(r.doc : node) = MP_JSON_NULL;
end-proc;

dcl-proc QueryResult_getInt export;
  dcl-pi *n int(20);
    resultH like(MP_QueryResult_h) value;
    row     int(10) value;
    column  int(10) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return mp_json_int(r.doc : cellNode(pr : row : column));
end-proc;

dcl-proc QueryResult_getDecimal export;
  dcl-pi *n packed(63:15);
    resultH like(MP_QueryResult_h) value;
    row     int(10) value;
    column  int(10) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  dcl-s  t  varchar(128);
  pr = checkResult(resultH);
  t = %trim(mp_json_text(r.doc : cellNode(pr : row : column)));
  if t = '';
    return 0;
  endif;
  monitor;
    if %scan('e' : t) > 0 or %scan('E' : t) > 0;
      return %dech(%float(t) : 63 : 15);
    endif;
    return %dech(t : 63 : 15);
  on-error;
    mp_throw('Mapepire: value ''' + t + ''' is not numeric');
  endmon;
  return 0;
end-proc;

dcl-proc QueryResult_getField export;
  dcl-pi *n varchar(MP_VALUE_MAX:4);
    resultH like(MP_QueryResult_h) value;
    name    varchar(128) const;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return mp_json_text(r.doc : mp_json_member(r.doc : 1 : name));
end-proc;

dcl-proc QueryResult_getOutputParmCount export;
  dcl-pi *n int(10);
    resultH like(MP_QueryResult_h) value;
  end-pi;
  dcl-ds r  likeds(QueryResult_t) based(pr);
  dcl-s  pr pointer;
  pr = checkResult(resultH);
  return mp_json_count(r.doc : mp_json_member(r.doc : 1 : 'output_parms'));
end-proc;

dcl-proc QueryResult_getOutputParm export;
  dcl-pi *n varchar(MP_VALUE_MAX:4);
    resultH like(MP_QueryResult_h) value;
    index   int(10) value;
  end-pi;
  dcl-ds r    likeds(QueryResult_t) based(pr);
  dcl-s  pr   pointer;
  dcl-s  parms int(10);
  dcl-s  node int(10);
  pr = checkResult(resultH);
  parms = mp_json_member(r.doc : 1 : 'output_parms');
  // find the element whose "index" matches (1-based parameter number)
  node = mp_json_first(r.doc : parms);
  dow node > 0;
    if mp_json_int(r.doc : mp_json_member(r.doc : node : 'index')) = index;
      return mp_json_text(r.doc : mp_json_member(r.doc : node : 'value'));
    endif;
    node = mp_json_next(r.doc : node);
  enddo;
  mp_throw('Mapepire: output parameter ' + %char(index) + ' does not exist');
  return '';
end-proc;

// ===========================================================================
//  Params
// ===========================================================================
dcl-proc Params_new export;
  dcl-pi *n like(MP_Params_h);
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = %alloc(%size(Params_t));
  clear p;
  p.eye = EYE_PARAMS;
  return pp;
end-proc;

dcl-proc checkParams;
  dcl-pi *n pointer;
    pp pointer value;
  end-pi;
  dcl-ds p likeds(Params_t) based(pp);
  if pp = *null;
    mp_throw('Mapepire: Params handle is *NULL');
  endif;
  if p.eye <> EYE_PARAMS;
    mp_throw('Mapepire: not a valid Params handle');
  endif;
  return pp;
end-proc;

// separator before the next value of the current set
dcl-proc nextValue;
  dcl-pi *n;
    pp pointer value;
  end-pi;
  dcl-ds p likeds(Params_t) based(pp);
  if p.curCount > 0;
    mp_buf_addByte(p.cur : 44);
  endif;
  p.curCount += 1;
end-proc;

dcl-proc Params_addString export;
  dcl-pi *n;
    paramsH like(MP_Params_h) value;
    value   varchar(MP_VALUE_MAX:4) const;
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = checkParams(paramsH);
  nextValue(pp);
  mp_json_quoteText(p.cur : value);
end-proc;

dcl-proc Params_addInt export;
  dcl-pi *n;
    paramsH like(MP_Params_h) value;
    value   int(20) value;
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = checkParams(paramsH);
  nextValue(pp);
  mp_buf_addText(p.cur : %char(value));
end-proc;

dcl-proc Params_addDecimal export;
  dcl-pi *n;
    paramsH like(MP_Params_h) value;
    value   packed(63:15) value;
  end-pi;
  dcl-ds p   likeds(Params_t) based(pp);
  dcl-s  pp  pointer;
  dcl-s  t   varchar(80);
  dcl-s  neg ind;

  pp = checkParams(paramsH);
  // JSON number: no leading '.', no trailing zeros
  neg = value < 0;
  t = %char(%abs(value));
  if %scan('.' : t) > 0;
    t = %trimr(t : '0');
    t = %trimr(t : '.');
  endif;
  if t = '' or %subst(t : 1 : 1) = '.';
    t = '0' + t;
  endif;
  if neg;
    t = '-' + t;
  endif;
  nextValue(pp);
  mp_buf_addText(p.cur : t);
end-proc;

dcl-proc Params_addBoolean export;
  dcl-pi *n;
    paramsH like(MP_Params_h) value;
    value   ind value;
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = checkParams(paramsH);
  nextValue(pp);
  if value;
    mp_buf_addText(p.cur : 'true');
  else;
    mp_buf_addText(p.cur : 'false');
  endif;
end-proc;

dcl-proc Params_addNull export;
  dcl-pi *n;
    paramsH like(MP_Params_h) value;
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = checkParams(paramsH);
  nextValue(pp);
  mp_buf_addText(p.cur : 'null');
end-proc;

dcl-proc Params_newRow export;
  dcl-pi *n;
    paramsH like(MP_Params_h) value;
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = checkParams(paramsH);
  p.isBatch = *on;
  if p.curCount = 0;
    return;
  endif;
  flushRow(pp);
end-proc;

dcl-proc flushRow;
  dcl-pi *n;
    pp pointer value;
  end-pi;
  dcl-ds p likeds(Params_t) based(pp);
  if p.rowCount > 0;
    mp_buf_addByte(p.rows : 44);
  endif;
  mp_buf_addByte(p.rows : 91);
  mp_buf_addBytes(p.rows : p.cur.data : p.cur.len);
  mp_buf_addByte(p.rows : 93);
  p.rowCount += 1;
  p.cur.len = 0;
  p.curCount = 0;
end-proc;

dcl-proc mp_params_toJson export;
  dcl-pi *n;
    paramsH pointer value;
    outBuf     likeds(mp_Buffer_t);
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  pp = checkParams(paramsH);
  outBuf.len = 0;
  mp_buf_addByte(outBuf : 91);
  if p.isBatch;
    mp_buf_addBytes(outBuf : p.rows.data : p.rows.len);
    if p.curCount > 0;
      if p.rowCount > 0;
        mp_buf_addByte(outBuf : 44);
      endif;
      mp_buf_addByte(outBuf : 91);
      mp_buf_addBytes(outBuf : p.cur.data : p.cur.len);
      mp_buf_addByte(outBuf : 93);
    endif;
  else;
    mp_buf_addBytes(outBuf : p.cur.data : p.cur.len);
  endif;
  mp_buf_addByte(outBuf : 93);
end-proc;

dcl-proc Params_free export;
  dcl-pi *n;
    paramsH like(MP_Params_h);
  end-pi;
  dcl-ds p  likeds(Params_t) based(pp);
  dcl-s  pp pointer;
  if paramsH = *null;
    return;
  endif;
  pp = checkParams(paramsH);
  mp_buf_free(p.cur);
  mp_buf_free(p.rows);
  p.eye = EYE_FREED;
  dealloc pp;
  paramsH = *null;
end-proc;

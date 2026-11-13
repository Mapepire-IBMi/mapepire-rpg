**FREE
// ===========================================================================
//  MPTEST - integration tests for the Mapepire RPG client
//
//  Needs a running mapepire-server. Configuration comes from environment
//  variables (ADDENVVAR, or exported in the PASE shell that runs SYSTEM):
//
//    MAPEPIRE_HOST       server host name               (required)
//    MAPEPIRE_PORT       port                           (default 8076)
//    MAPEPIRE_USER       user profile                   (required)
//    MAPEPIRE_PASSWORD   password                       (required)
//    MAPEPIRE_CA_FILE    PEM of the server certificate  (required)
//    MAPEPIRE_TEST_LIB   library for test objects       (default QTEMP)
//    MAPEPIRE_UNTRUSTED  PEM of some OTHER certificate  (optional)
//
//  Environment variables are not inherited by the job that PASE's SYSTEM
//  command starts, so the same settings can also come from a file of
//  KEY=value lines whose path is passed as the only parameter:
//
//    CALL MPTEST PARM('/home/me/mptest.conf')
//
//  Results are written to stdout; the program ends with an escape message
//  when a test failed.
// ===========================================================================
ctl-opt main(main) ccsid(*char:*jobrun)
        option(*srcstmt:*nodebugio) bnddir('QC2LE');

/copy mapepire.rpgleinc

dcl-pr printf int(10) extproc('printf');
  fmt pointer value options(*string);
  arg pointer value options(*string:*nopass);
end-pr;

dcl-pr getenv pointer extproc('getenv');
  name pointer value options(*string);
end-pr;

dcl-pr QMHSNDPM extpgm('QMHSNDPM');
  msgId      char(7) const;
  msgFile    char(20) const;
  msgData    char(512) const options(*varsize);
  msgDataLen int(10) const;
  msgType    char(10) const;
  stackEntry char(10) const;
  stackCount int(10) const;
  msgKey     char(4);
  err        char(8);
end-pr;

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

dcl-c O_RDONLY   1;
dcl-c O_TEXTDATA 16777216;

// settings read from the config file
dcl-s fileCount  int(10) inz(0);
dcl-s fileKeys   varchar(64) dim(32);
dcl-s fileValues varchar(1024) dim(32);

dcl-ds cfg qualified;
  host      varchar(255);
  port      int(10);
  user      varchar(128);
  password  varchar(128);
  caFile    varchar(1024);
  lib       varchar(10);
  untrusted varchar(1024);
end-ds;

dcl-ds psds psds qualified;
  msgId   char(7)  pos(40);
  excData char(80) pos(91);
end-ds;

dcl-s passed int(10) inz(0);
dcl-s failed int(10) inz(0);
dcl-s current varchar(80);

// one connected job shared by most tests
dcl-s job like(MP_SQLJob_h);

// ===========================================================================
dcl-proc main;
  dcl-pi *n;
    configFile char(256) const options(*nopass);
  end-pi;
  dcl-s path varchar(256) inz('');
  dcl-s blank int(10);
  if %parms >= 1;
    // CL pads short literals only to 32 bytes: stop at the first blank
    blank = %scan(' ' : configFile);
    if blank = 0;
      path = configFile;
    elseif blank > 1;
      path = %subst(configFile : 1 : blank - 1);
    endif;
  endif;
  if path <> '';
    readConfigFile(path);
  endif;
  loadConfig();
  say('Mapepire RPG client tests against ' + cfg.host + ':'
      + %char(cfg.port));

  testConnect();
  if job <> *null and SQLJob_getStatus(job) = MP_JOB_READY;
    testServerInfo();
    testSimpleQuery();
    testColumnMetadata();
    testPaging();
    testTerse();
    testParameters();
    testEscapesAndUnicode();
    testDml();
    testBatchAndExecute();
    testOutputParameters();
    testSqlError();
    testClCommand();
    testQueryAndRun();
    testAutoClose();
    testLargeResult();
    testLargeRequest();
    testExplain();
    testInvalidHandles();
    testClose();
  endif;
  testBadPassword();
  testDefaultValidationRejectsSelfSigned();
  testWrongPinnedCert();

  SQLJob_free(job);

  say('');
  say(%char(passed) + ' passed, ' + %char(failed) + ' failed');
  if failed > 0;
    escape(%char(failed) + ' Mapepire RPG test(s) failed');
  endif;
end-proc;

// ===========================================================================
//  Tests
// ===========================================================================
dcl-proc testConnect;
  dcl-ds conn likeds(MP_ConnectionResult_t);
  begin('connect with pinned certificate');
  monitor;
    job = SQLJob_new();
    check(SQLJob_getStatus(job) = MP_JOB_NOT_STARTED : 'status notStarted');
    conn = SQLJob_connect(job : server());
    check(conn.base.success : 'connect succeeded');
    check(conn.job <> '' : 'server job name returned: ' + conn.job);
    check(SQLJob_getStatus(job) = MP_JOB_READY : 'status ready');
    check(SQLJob_getId(job) = conn.job : 'SQLJob_getId = job name');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testServerInfo;
  dcl-ds ver  likeds(MP_VersionResult_t);
  dcl-ds ping likeds(MP_PingResult_t);
  begin('version, ping and getdbjob');
  monitor;
    ver = SQLJob_getVersion(job);
    check(ver.base.success and ver.version <> ''
          : 'version ' + ver.version + ' (' + ver.buildDate + ')');
    ping = SQLJob_ping(job);
    check(ping.alive and ping.dbAlive : 'ping alive / db_alive');
    check(SQLJob_getDbJob(job) = SQLJob_getId(job) : 'getdbjob = job id');
    check(SQLJob_getUniqueId(job : 'x') <> SQLJob_getUniqueId(job : 'x')
          : 'unique ids differ');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testSimpleQuery;
  dcl-s q like(MP_Query_h);
  dcl-s r like(MP_QueryResult_h);
  dcl-ds s likeds(MP_QueryResult_t);
  begin('simple query');
  monitor;
    q = SQLJob_query(job : 'values (1, ''abc'', cast(null as int), '
                         + 'cast(12.50 as decimal(5,2)), current date)');
    check(Query_getState(q) = MP_QUERY_NOT_YET_RUN : 'state NOT_YET_RUN');
    r = Query_run(q);
    s = QueryResult_get(r);
    check(s.base.success : 'success');
    check(s.hasResults : 'has_results');
    check(s.isDone : 'is_done');
    check(s.rowCount = 1 : 'one row');
    check(s.columnCount = 5 : 'five columns');
    check(QueryResult_getInt(r : 1 : 1) = 1 : 'int value');
    checkEq(QueryResult_getValue(r : 1 : 2) : 'abc' : 'string value');
    check(QueryResult_isNull(r : 1 : 3) : 'null value');
    check(not QueryResult_isNull(r : 1 : 2) : 'non-null value');
    check(QueryResult_getDecimal(r : 1 : 4) = 12.5 : 'decimal value');
    // formatted with the server job's date format
    check(%len(QueryResult_getValue(r : 1 : 5)) >= 8 : 'date value '
          + QueryResult_getValue(r : 1 : 5));
    check(Query_getState(q) = MP_QUERY_RUN_DONE : 'state RUN_DONE');
    check(Query_getId(q) <> '' : 'correlation id ' + Query_getId(q));
    Query_free(q);
    check(q = *null : 'Query_free clears the handle');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testColumnMetadata;
  dcl-s r like(MP_QueryResult_h);
  dcl-ds col likeds(MP_ColumnMetaData_t);
  begin('column metadata');
  monitor;
    r = SQLJob_queryAndRun(job : 'select cast(''x'' as char(7)) as CODE, '
        + 'cast(1.5 as decimal(9,3)) as AMOUNT from sysibm.sysdummy1');
    col = QueryResult_getColumn(r : 1);
    checkEq(col.name : 'CODE' : 'name');
    checkEq(col.type : 'CHAR' : 'type');
    check(col.precision = 7 : 'precision');
    col = QueryResult_getColumn(r : 2);
    checkEq(col.type : 'DECIMAL' : 'decimal type');
    check(col.precision = 9 and col.scale = 3 : 'precision / scale');
    check(QueryResult_getColumnIndex(r : 'AMOUNT') = 2 : 'index by name');
    check(QueryResult_getColumnIndex(r : 'amount') = 2 : 'case-insensitive');
    check(QueryResult_getColumnIndex(r : 'NOPE') = 0 : 'unknown column');
    checkEq(QueryResult_getValueByName(r : 1 : 'CODE') : 'x      '
            : 'value by name');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testPaging;
  dcl-s q like(MP_Query_h);
  dcl-s r like(MP_QueryResult_h);
  dcl-s total int(10) inz(0);
  dcl-s blocks int(10) inz(0);
  dcl-s raised ind inz(*off);
  dcl-s last int(10) inz(0);
  dcl-s i int(10);
  dcl-s ordered ind inz(*on);
  begin('paging with fetchMore');
  monitor;
    q = SQLJob_query(job : 'select ordinal_position from qsys2.syscolumns '
        + 'where table_schema = ''QSYS2'' and table_name = ''SYSCOLUMNS'' '
        + 'order by ordinal_position fetch first 25 rows only');
    r = Query_run(q : 10);
    check(QueryResult_getRowCount(r) = 10 : 'first block 10 rows');
    check(not QueryResult_isDone(r) : 'first block not done');
    check(Query_getState(q) = MP_QUERY_RUN_MORE_DATA_AVAIL
          : 'state RUN_MORE_DATA_AVAIL');
    dow *on;
      blocks += 1;
      for i = 1 to QueryResult_getRowCount(r);
        total += 1;
        if QueryResult_getInt(r : i : 1) <> last + 1;
          ordered = *off;
        endif;
        last = QueryResult_getInt(r : i : 1);
      endfor;
      if Query_getState(q) = MP_QUERY_RUN_DONE;
        leave;
      endif;
      QueryResult_free(r);
      r = Query_fetchMore(q);
    enddo;
    check(total = 25 : 'all 25 rows fetched (' + %char(total) + ')');
    check(blocks = 3 : '3 blocks (' + %char(blocks) + ')');
    check(ordered : 'rows in order across blocks');
    check(QueryResult_getColumnCount(r) = 1 : 'metadata kept for later blocks');
    monitor;
      Query_fetchMore(q);
    on-error;
      raised = *on;
    endmon;
    check(raised : 'fetchMore after RUN_DONE raises');
    raised = *off;
    monitor;
      Query_run(q);
    on-error;
      raised = *on;
    endmon;
    check(raised : 'run twice raises');
    Query_free(q);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testTerse;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s r like(MP_QueryResult_h);
  begin('terse results');
  monitor;
    opts.isTerseResults = *on;
    r = SQLJob_queryAndRun(job : 'values (7, ''seven'')' : opts);
    checkEq(QueryResult_getField(r : 'data') : '[[7,"seven"]]' : 'rows are arrays');
    check(QueryResult_getInt(r : 1 : 1) = 7 : 'int by position');
    checkEq(QueryResult_getValueByName(r : 1 : '00002') : 'seven'
            : 'string by name');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testParameters;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s p like(MP_Params_h);
  dcl-s r like(MP_QueryResult_h);
  dcl-ds summary likeds(MP_QueryResult_t);
  begin('prepared statement parameters');
  monitor;
    p = Params_new();
    Params_addString(p : 'hello');
    Params_addInt(p : -1234567890123);
    Params_addDecimal(p : -0.25);
    Params_addNull(p);
    Params_addBoolean(p : *on);
    Params_addDecimal(p : 1000);
    opts.parameters = p;
    r = SQLJob_queryAndRun(job : 'select cast(? as varchar(20)), '
        + 'cast(? as bigint), cast(? as decimal(10,2)), cast(? as int), '
        + 'cast(? as boolean), cast(? as int) from sysibm.sysdummy1' : opts);
    checkEq(QueryResult_getValue(r : 1 : 1) : 'hello' : 'string parameter');
    check(QueryResult_getInt(r : 1 : 2) = -1234567890123 : 'bigint parameter');
    check(QueryResult_getDecimal(r : 1 : 3) = -0.25 : 'decimal parameter');
    check(QueryResult_isNull(r : 1 : 4) : 'null parameter');
    checkEq(QueryResult_getValue(r : 1 : 5) : 'true' : 'boolean parameter');
    check(QueryResult_getInt(r : 1 : 6) = 1000 : 'whole decimal parameter');
    summary = QueryResult_get(r);
    check(summary.parameterCount = 6 : 'parameter_count');
    QueryResult_free(r);
    Params_free(p);
    check(p = *null : 'Params_free clears the handle');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testEscapesAndUnicode;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s p like(MP_Params_h);
  dcl-s r like(MP_QueryResult_h);
  dcl-s tricky varchar(100);
  dcl-s accents varchar(20);
  begin('escaping and unicode round trip');
  monitor;
    // quote, backslash, slash, tab, newline, apostrophe
    tricky = 'a"b\c/d' + x'05' + 'e' + x'25' + 'f''g';
    // e-acute, n-tilde, u-umlaut, cent sign: converted from UCS-2
    accents = %char(u'00E900F100FC00A2');
    p = Params_new();
    Params_addString(p : tricky);
    Params_addString(p : accents);
    Params_addString(p : accents);
    opts.parameters = p;
    r = SQLJob_queryAndRun(job : 'values (cast(? as varchar(100)), '
        + 'cast(? as varchar(20)), length(cast(? as varchar(20))))'
        : opts);
    checkEq(QueryResult_getValue(r : 1 : 1) : tricky : 'special characters');
    checkEq(QueryResult_getValue(r : 1 : 2) : accents : 'accented characters');
    check(QueryResult_getInt(r : 1 : 3) = 4 : 'server sees 4 characters');
    QueryResult_free(r);
    Params_free(p);

    // a server side string that JSON escapes (' for apostrophe)
    r = SQLJob_queryAndRun(job : 'values ''it''''s'' concat chr(10) '
        + 'concat ''<&>''');
    checkEq(QueryResult_getValue(r : 1 : 1) : 'it''s' + x'25' + '<&>'
            : 'escaped server text');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testDml;
  dcl-s r like(MP_QueryResult_h);
  dcl-s t varchar(40);
  dcl-ds summary likeds(MP_QueryResult_t);
  begin('DDL and DML');
  monitor;
    t = cfg.lib + '.MPRPGTST';
    dropTable(t);
    r = SQLJob_queryAndRun(job : 'create table ' + t
        + ' (id int not null primary key, name varchar(50), '
        + 'amount decimal(9,2))');
    check(QueryResult_isSuccess(r) : 'create table');
    QueryResult_free(r);
    r = SQLJob_queryAndRun(job : 'insert into ' + t
        + ' values (1, ''one'', 1.10), (2, ''two'', 2.20), '
        + '(3, ''three'', 3.30)');
    check(QueryResult_getUpdateCount(r) = 3 : 'insert update_count 3');
    summary = QueryResult_get(r);
    check(not summary.hasResults : 'insert has no results');
    QueryResult_free(r);
    r = SQLJob_queryAndRun(job : 'update ' + t
        + ' set amount = amount * 2 where id >= 2');
    check(QueryResult_getUpdateCount(r) = 2 : 'update update_count 2');
    QueryResult_free(r);
    r = SQLJob_queryAndRun(job : 'select sum(amount) from ' + t);
    check(QueryResult_getDecimal(r : 1 : 1) = 12.10 : 'sum after update');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testBatchAndExecute;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s p like(MP_Params_h);
  dcl-s p2 like(MP_Params_h);
  dcl-s q like(MP_Query_h);
  dcl-s r like(MP_QueryResult_h);
  dcl-s t varchar(40);
  dcl-s i int(10);
  begin('batch insert and re-execute');
  monitor;
    t = cfg.lib + '.MPRPGTST';
    p = Params_new();
    for i = 10 to 14;
      Params_addInt(p : i);
      Params_addString(p : 'batch ' + %char(i));
      Params_addDecimal(p : i / 4);
      Params_newRow(p);
    endfor;
    opts.parameters = p;
    r = SQLJob_queryAndRun(job : 'insert into ' + t + ' values (?, ?, ?)'
                           : opts);
    check(QueryResult_isSuccess(r) : 'batch insert');
    QueryResult_free(r);
    Params_free(p);

    r = SQLJob_queryAndRun(job : 'select count(*) from ' + t
                           + ' where id between 10 and 14');
    check(QueryResult_getInt(r : 1 : 1) = 5 : '5 batch rows inserted');
    QueryResult_free(r);

    // prepare once, execute with different values
    p = Params_new();
    Params_addInt(p : 1);
    opts.parameters = p;
    q = SQLJob_query(job : 'select name from ' + t + ' where id = ?' : opts);
    r = Query_run(q);
    checkEq(QueryResult_getValue(r : 1 : 1) : 'one' : 'first execution');
    p2 = Params_new();
    Params_addInt(p2 : 12);
    r = Query_execute(q : p2);
    checkEq(QueryResult_getValue(r : 1 : 1) : 'batch 12' : 're-execution');
    Params_free(p);
    Params_free(p2);
    Query_free(q);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testOutputParameters;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s p like(MP_Params_h);
  dcl-s r like(MP_QueryResult_h);
  dcl-s proc varchar(40);
  begin('CALL with output parameters');
  monitor;
    proc = cfg.lib + '.MPRPGPROC';
    r = SQLJob_queryAndRun(job : 'create or replace procedure ' + proc
        + ' (in a int, inout b varchar(20), out c int) '
        + 'begin set c = a * 2; set b = b concat ''!''; end');
    QueryResult_free(r);
    p = Params_new();
    Params_addInt(p : 21);
    Params_addString(p : 'hi');
    // OUT parameters still need a (non-null) placeholder value
    Params_addInt(p : 0);
    opts.parameters = p;
    r = SQLJob_queryAndRun(job : 'call ' + proc + '(?, ?, ?)' : opts);
    check(QueryResult_getOutputParmCount(r) >= 2 : 'output_parms returned');
    checkEq(QueryResult_getOutputParm(r : 2) : 'hi!' : 'INOUT parameter');
    checkEq(QueryResult_getOutputParm(r : 3) : '42' : 'OUT parameter');
    QueryResult_free(r);
    Params_free(p);
    r = SQLJob_queryAndRun(job : 'drop procedure ' + proc);
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testSqlError;
  dcl-s q like(MP_Query_h);
  dcl-s raised ind inz(*off);
  dcl-ds err likeds(MP_ServerResponse_t);
  begin('SQL error raises');
  monitor;
    q = SQLJob_query(job : 'select * from NOSUCHLIB.NOSUCHFILE');
    monitor;
      Query_run(q);
    on-error;
      raised = *on;
    endmon;
    check(raised : 'Query_run raised an exception');
    err = MP_getLastError();
    check(not err.success : 'last error recorded');
    checkEq(err.sqlState : '42704' : 'SQLSTATE 42704');
    check(err.sqlRc = -204 : 'SQLCODE -204');
    check(%scan('SQL0204' : err.error) > 0 : 'message text: ' + err.error);
    check(Query_getState(q) = MP_QUERY_ERROR : 'state ERROR');
    Query_free(q);
    check(SQLJob_getStatus(job) = MP_JOB_READY : 'job still ready');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testClCommand;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s r like(MP_QueryResult_h);
  dcl-s i int(10);
  dcl-s found ind inz(*off);
  begin('CL commands');
  monitor;
    opts.isClCommand = *on;
    r = SQLJob_queryAndRun(job : 'CHGJOB LOG(4 00 *SECLVL)' : opts);
    check(QueryResult_isSuccess(r) : 'CHGJOB succeeded');
    QueryResult_free(r);
    // a failing command does not raise; the job log comes back instead
    r = SQLJob_queryAndRun(job : 'DLTLIB LIB(MPNOSUCHLB)' : opts);
    check(not QueryResult_isSuccess(r) : 'DLTLIB failed');
    for i = 1 to QueryResult_getRowCount(r);
      if QueryResult_getValueByName(r : i : 'MESSAGE_ID') = 'CPF2110';
        found = *on;
      endif;
    endfor;
    check(found : 'CPF2110 in the job log rows');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testQueryAndRun;
  dcl-s r like(MP_QueryResult_h);
  begin('queryAndRun ownership');
  monitor;
    r = SQLJob_queryAndRun(job : 'values 1' : *omit : 5);
    check(QueryResult_getInt(r : 1 : 1) = 1 : 'value');
    QueryResult_free(r);
    check(r = *null : 'QueryResult_free clears the handle');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testAutoClose;
  dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-s q like(MP_Query_h);
  dcl-s r like(MP_QueryResult_h);
  begin('autoClose');
  monitor;
    opts.autoClose = *on;
    q = SQLJob_query(job : 'values 1, 2, 3' : opts);
    r = Query_run(q : 2);
    check(Query_getState(q) = MP_QUERY_RUN_MORE_DATA_AVAIL : 'more data');
    r = Query_fetchMore(q : 2);
    check(Query_getState(q) = MP_QUERY_RUN_DONE : 'done after last block');
    check(QueryResult_getRowCount(r) = 1 : 'last row');
    Query_free(q);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testLargeResult;
  dcl-s r like(MP_QueryResult_h);
  dcl-s i int(10);
  dcl-s ok ind inz(*on);
  begin('large result (5000 rows in one block)');
  monitor;
    r = SQLJob_queryAndRun(job : 'with n(i) as (values 1 union all '
        + 'select i + 1 from n where i < 5000) '
        + 'select i, repeat(''x'', 100) concat i from n' : *omit : 5000);
    check(QueryResult_getRowCount(r) = 5000 : '5000 rows');
    for i = 1 to 5000;
      if QueryResult_getInt(r : i : 1) <> i;
        ok = *off;
      endif;
    endfor;
    check(ok : 'every row in order');
    check(%len(QueryResult_getValue(r : 5000 : 2)) = 104 : 'wide values');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testLargeRequest;
  dcl-s r like(MP_QueryResult_h);
  dcl-s sql varchar(200000);
  begin('large request (> 64 KB frame)');
  monitor;
    // Db2 limits the length of one comment, so use many line comments
    sql = 'values 42';
    dow %len(sql) < 150000;
      sql += x'25' + '-- ' + padding(100);
    enddo;
    r = SQLJob_queryAndRun(job : sql);
    check(QueryResult_getInt(r : 1 : 1) = 42 : '150 KB statement ran');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testExplain;
  dcl-s r like(MP_QueryResult_h);
  begin('Visual Explain');
  monitor;
    r = SQLJob_explain(job : 'select * from sysibm.sysdummy1');
    check(QueryResult_isSuccess(r) : 'dove succeeded');
    check(QueryResult_getRowCount(r) > 0 : 'explain rows: '
          + %char(QueryResult_getRowCount(r)));
    check(QueryResult_getColumnCount(r) > 0 : 'explain columns');
    QueryResult_free(r);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testInvalidHandles;
  dcl-s bogus pointer;
  dcl-s raised ind inz(*off);
  dcl-s junk char(64) inz('junk');
  begin('invalid handles raise');
  monitor;
    monitor;
      Query_getState(*null);
    on-error;
      raised = *on;
    endmon;
    check(raised : '*NULL query handle');
    raised = *off;
    bogus = %addr(junk);
    monitor;
      QueryResult_getRowCount(bogus);
    on-error;
      raised = *on;
    endmon;
    check(raised : 'garbage result handle');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testClose;
  dcl-s raised ind inz(*off);
  begin('close');
  monitor;
    dropTable(cfg.lib + '.MPRPGTST');
    SQLJob_close(job);
    check(SQLJob_getStatus(job) = MP_JOB_ENDED : 'status ended');
    monitor;
      SQLJob_queryAndRun(job : 'values 1');
    on-error;
      raised = *on;
    endmon;
    check(raised : 'query after close raises');
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testBadPassword;
  dcl-s j like(MP_SQLJob_h);
  dcl-ds srv likeds(MP_DaemonServer_t);
  dcl-ds err likeds(MP_ServerResponse_t);
  dcl-s raised ind inz(*off);
  begin('wrong password is rejected');
  monitor;
    srv = server();
    srv.password = 'not-the-password';
    j = SQLJob_new();
    monitor;
      SQLJob_connect(j : srv);
    on-error;
      raised = *on;
    endmon;
    err = MP_getLastError();
    check(raised : 'connect raised: ' + err.error);
    check(SQLJob_getStatus(j) = MP_JOB_NOT_STARTED : 'status notStarted');
    SQLJob_free(j);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testDefaultValidationRejectsSelfSigned;
  dcl-s j like(MP_SQLJob_h);
  dcl-ds srv likeds(MP_DaemonServer_t);
  dcl-ds err likeds(MP_ServerResponse_t);
  dcl-s raised ind inz(*off);
  begin('default TLS validation rejects an untrusted certificate');
  monitor;
    srv = server();
    srv.caFile = '';
    j = SQLJob_new();
    monitor;
      SQLJob_connect(j : srv);
    on-error;
      raised = *on;
    endmon;
    err = MP_getLastError();
    check(raised : 'connect raised: ' + err.error);
    SQLJob_free(j);
  on-error;
    exception();
  endmon;
end-proc;

dcl-proc testWrongPinnedCert;
  dcl-s j like(MP_SQLJob_h);
  dcl-ds srv likeds(MP_DaemonServer_t);
  dcl-ds err likeds(MP_ServerResponse_t);
  dcl-s raised ind inz(*off);
  begin('a different pinned certificate is rejected');
  if cfg.untrusted = '';
    say('  (skipped: MAPEPIRE_UNTRUSTED not set)');
    return;
  endif;
  monitor;
    srv = server();
    srv.caFile = cfg.untrusted;
    j = SQLJob_new();
    monitor;
      SQLJob_connect(j : srv);
    on-error;
      raised = *on;
    endmon;
    err = MP_getLastError();
    check(raised and %scan('does not match' : err.error) > 0
          : 'connect raised: ' + err.error);
    SQLJob_free(j);
  on-error;
    exception();
  endmon;
end-proc;

// ===========================================================================
//  Helpers
// ===========================================================================
dcl-proc server;
  dcl-pi *n likeds(MP_DaemonServer_t);
  end-pi;
  dcl-ds srv likeds(MP_DaemonServer_t) inz(*likeds);
  srv.host = cfg.host;
  srv.port = cfg.port;
  srv.user = cfg.user;
  srv.password = cfg.password;
  srv.caFile = cfg.caFile;
  srv.timeout = 120;
  return srv;
end-proc;

dcl-proc dropTable;
  dcl-pi *n;
    name varchar(40) const;
  end-pi;
  dcl-s r like(MP_QueryResult_h);
  monitor;
    r = SQLJob_queryAndRun(job : 'drop table ' + name);
    QueryResult_free(r);
  on-error;
  endmon;
end-proc;

dcl-proc padding;
  dcl-pi *n varchar(200000);
    n int(10) value;
  end-pi;
  dcl-s s varchar(200000);
  s = '';
  dow %len(s) < n;
    s += 'padding.. ';
  enddo;
  return %subst(s : 1 : n);
end-proc;

dcl-proc loadConfig;
  cfg.host = env('MAPEPIRE_HOST');
  cfg.user = env('MAPEPIRE_USER');
  cfg.password = env('MAPEPIRE_PASSWORD');
  cfg.caFile = env('MAPEPIRE_CA_FILE');
  cfg.lib = env('MAPEPIRE_TEST_LIB');
  cfg.untrusted = env('MAPEPIRE_UNTRUSTED');
  if cfg.lib = '';
    cfg.lib = 'QTEMP';
  endif;
  cfg.port = 8076;
  if env('MAPEPIRE_PORT') <> '';
    cfg.port = %int(env('MAPEPIRE_PORT'));
  endif;
  if cfg.host = '' or cfg.user = '' or cfg.password = '' or cfg.caFile = '';
    escape('Set MAPEPIRE_HOST, MAPEPIRE_USER, MAPEPIRE_PASSWORD and '
           + 'MAPEPIRE_CA_FILE');
  endif;
end-proc;

dcl-proc env;
  dcl-pi *n varchar(1024);
    name varchar(64) const;
  end-pi;
  dcl-s p pointer;
  dcl-s i int(10);
  p = getenv(name);
  if p <> *null;
    return %str(p);
  endif;
  for i = 1 to fileCount;
    if fileKeys(i) = name;
      return fileValues(i);
    endif;
  endfor;
  return '';
end-proc;

// KEY=value lines (job CCSID conversion by the file system)
dcl-proc readConfigFile;
  dcl-pi *n;
    path varchar(256) const;
  end-pi;
  dcl-s fd    int(10);
  dcl-s buf   char(8192);
  dcl-s n     int(10);
  dcl-s text  varchar(8192);
  dcl-s line  varchar(1024);
  dcl-s eol   int(10);
  dcl-s eq    int(10);

  fd = c_open(path : O_RDONLY + O_TEXTDATA);
  if fd < 0;
    escape('Cannot open config file ' + path);
  endif;
  n = c_read(fd : %addr(buf) : %size(buf));
  c_close(fd);
  if n <= 0;
    return;
  endif;
  text = %subst(buf : 1 : n);
  dow text <> '' and fileCount < %elem(fileKeys);
    eol = %scan(x'25' : text);
    if eol = 0;
      line = text;
      text = '';
    else;
      line = %subst(text : 1 : eol - 1);
      if eol >= %len(text);
        text = '';
      else;
        text = %subst(text : eol + 1);
      endif;
    endif;
    line = %trim(%xlate(x'0D' : ' ' : line));
    eq = %scan('=' : line);
    if eq > 1 and %subst(line : 1 : 1) <> '#';
      fileCount += 1;
      fileKeys(fileCount) = %trim(%subst(line : 1 : eq - 1));
      fileValues(fileCount) = %trim(%subst(line : eq + 1));
    endif;
  enddo;
end-proc;

dcl-proc begin;
  dcl-pi *n;
    name varchar(80) const;
  end-pi;
  current = name;
  say('- ' + name);
end-proc;

dcl-proc check;
  dcl-pi *n;
    cond ind value;
    what varchar(1024) const;
  end-pi;
  if cond;
    passed += 1;
    say('    ok    ' + what);
  else;
    failed += 1;
    say('    FAIL  ' + what);
  endif;
end-proc;

dcl-proc checkEq;
  dcl-pi *n;
    actual   varchar(MP_VALUE_MAX:4) const;
    expected varchar(MP_VALUE_MAX:4) const;
    what     varchar(256) const;
  end-pi;
  if actual = expected;
    check(*on : what);
  else;
    check(*off : what + ': expected [' + %subst(expected : 1
          : %min(%len(expected) : 200)) + '] got [' + %subst(actual : 1
          : %min(%len(actual) : 200)) + ']');
  endif;
end-proc;

dcl-proc exception;
  dcl-ds err likeds(MP_ServerResponse_t);
  err = MP_getLastError();
  check(*off : 'unexpected exception in "' + current + '": ' + err.error
        + ' [' + psds.msgId + ' ' + %trim(psds.excData) + ']');
end-proc;

dcl-proc say;
  dcl-pi *n;
    text varchar(2048) const;
  end-pi;
  printf('%s' + x'25' : %trimr(text));
end-proc;

dcl-proc escape;
  dcl-pi *n;
    text varchar(512) const;
  end-pi;
  dcl-s key char(4);
  dcl-s err char(8) inz(x'0000000000000000');
  QMHSNDPM('CPF9898' : 'QCPFMSG   *LIBL' : text : %len(text) : '*ESCAPE'
           : '*PGMBDY' : 1 : key : err);
end-proc;

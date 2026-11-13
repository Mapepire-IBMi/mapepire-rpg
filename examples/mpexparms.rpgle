**FREE
// ===========================================================================
//  MPEXPARMS - prepared statements, batch insert, SQL errors, CL commands
//
//    CALL MPEXPARMS PARM('myibmi.example.com' 'MYUSER' 'mypassword'
//                        '/home/myuser/mapepire-server.pem' 'MYLIB')
// ===========================================================================
ctl-opt main(main) ccsid(*char:*jobrun) bnddir('QC2LE');

/copy mapepire.rpgleinc

dcl-pr printf int(10) extproc('printf');
  fmt pointer value options(*string);
  arg pointer value options(*string:*nopass);
end-pr;

dcl-proc main;
  dcl-pi *n;
    host     char(64) const;
    user     char(10) const;
    password char(128) const;
    caFile   char(256) const;
    library  char(10) const;
  end-pi;

  dcl-s job    like(MP_SQLJob_h);
  dcl-s parms  like(MP_Params_h);
  dcl-s result like(MP_QueryResult_h);
  dcl-ds server  likeds(MP_DaemonServer_t) inz(*likeds);
  dcl-ds jobOpts likeds(MP_JobOptions_t) inz(*likeds);
  dcl-ds opts    likeds(MP_QueryOptions_t) inz(*likeds);
  dcl-ds err     likeds(MP_ServerResponse_t);
  dcl-s  i       int(10);
  dcl-s  lib     varchar(10);
  dcl-s  table   varchar(21);

  lib = word(library : %size(library));
  server.host = word(host : %size(host));
  server.user = word(user : %size(user));
  server.password = word(password : %size(password));
  server.caFile = word(caFile : %size(caFile));
  table = lib + '/MPEXDEMO';
  // JDBC properties: system naming (LIB/FILE) and a library list
  jobOpts.props = 'naming=system;libraries=' + lib;

  monitor;
    job = SQLJob_new(jobOpts);
    SQLJob_connect(job : server);

    result = SQLJob_queryAndRun(job : 'create or replace table ' + table
           + ' (id int, name varchar(30), price decimal(9,2))');
    QueryResult_free(result);

    // batch insert: one parameter set per row
    parms = Params_new();
    for i = 1 to 3;
      Params_addInt(parms : i);
      Params_addString(parms : 'Item ' + %char(i));
      Params_addDecimal(parms : i * 1.25);
      Params_newRow(parms);
    endfor;
    opts.parameters = parms;
    result = SQLJob_queryAndRun(job : 'insert into ' + table + ' values (?, ?, ?)'
                                : opts);
    QueryResult_free(result);
    Params_free(parms);

    // query with a parameter marker
    parms = Params_new();
    Params_addDecimal(parms : 2);
    opts.parameters = parms;
    result = SQLJob_queryAndRun(job : 'select id, name, price from ' + table
                                + ' where price >= ? order by id' : opts);
    for i = 1 to QueryResult_getRowCount(result);
      say(%char(QueryResult_getInt(result : i : 1)) + ' '
          + QueryResult_getValue(result : i : 2) + ' '
          + %char(QueryResult_getDecimal(result : i : 3)));
    endfor;
    QueryResult_free(result);
    Params_free(parms);

    // SQL errors raise CPF9898; the details are in MP_getLastError()
    monitor;
      result = SQLJob_queryAndRun(job : 'select * from NOSUCHTABLE');
    on-error;
      err = MP_getLastError();
      say('Expected error: SQLSTATE ' + err.sqlState + ' ' + err.error);
    endmon;

    // CL command: the result rows are the job log messages it produced
    clear opts;
    opts.isClCommand = *on;
    result = SQLJob_queryAndRun(job : 'DLTF FILE(' + table + ')'
                                : opts);
    say('DLTF success=' + QueryResult_isSuccess(result));
    for i = 1 to QueryResult_getRowCount(result);
      say('  ' + QueryResult_getValueByName(result : i : 'MESSAGE_ID') + ' '
          + QueryResult_getValueByName(result : i : 'MESSAGE_TEXT'));
    endfor;
    QueryResult_free(result);

    SQLJob_close(job);
  on-error;
    err = MP_getLastError();
    say('Failed: ' + err.error);
  endmon;
  SQLJob_free(job);
end-proc;

dcl-proc say;
  dcl-pi *n;
    text varchar(1024) const;
  end-pi;
  printf('%s' + x'25' : text);
end-proc;

// CL passes a literal longer than 32 bytes with exactly its own length, so
// a CHAR(n) parameter may contain unrelated storage after the value: use
// everything up to the first blank.
dcl-proc word;
  dcl-pi *n varchar(256);
    parm char(256) options(*varsize) const;
    size int(10) value;
  end-pi;
  dcl-s n int(10);
  n = %scan(' ' : %subst(parm : 1 : size));
  if n = 0;
    return %subst(parm : 1 : size);
  endif;
  return %subst(parm : 1 : n - 1);
end-proc;

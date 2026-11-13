**FREE
// ===========================================================================
//  MPEXQUERY - connect, run a query and page through the result
//
//    CALL MPEXQUERY PARM('myibmi.example.com' 'MYUSER' 'mypassword'
//                        '/home/myuser/mapepire-server.pem')
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
  end-pi;

  // "objects"
  dcl-s job    like(MP_SQLJob_h);
  dcl-s query  like(MP_Query_h);
  dcl-s result like(MP_QueryResult_h);

  dcl-ds server likeds(MP_DaemonServer_t) inz(*likeds);
  dcl-ds conn   likeds(MP_ConnectionResult_t);
  dcl-ds col    likeds(MP_ColumnMetaData_t);
  dcl-ds err    likeds(MP_ServerResponse_t);
  dcl-s  row    int(10);
  dcl-s  total  int(10) inz(0);

  server.host = word(host : %size(host));
  server.user = word(user : %size(user));
  server.password = word(password : %size(password));
  // the server's (self-signed) certificate that we trust
  server.caFile = word(caFile : %size(caFile));

  monitor;
    job = SQLJob_new();
    conn = SQLJob_connect(job : server);
    say('Connected; database job ' + conn.job);

    query = SQLJob_query(job : 'select table_schema, table_name, '
          + 'table_type from qsys2.systables where table_schema = ''QSYS2'' '
          + 'order by table_name fetch first 12 rows only');

    // first block of 5 rows, then fetchMore until the query is done
    result = Query_run(query : 5);
    col = QueryResult_getColumn(result : 2);
    say('Column 2 is ' + col.name + ' ' + col.type + '('
        + %char(col.precision) + ')');

    dow *on;
      for row = 1 to QueryResult_getRowCount(result);
        total += 1;
        say(%char(total) + ': '
            + QueryResult_getValueByName(result : row : 'TABLE_NAME') + ' ('
            + QueryResult_getValue(result : row : 3) + ')');
      endfor;
      QueryResult_free(result);
      if Query_getState(query) = MP_QUERY_RUN_DONE;
        leave;
      endif;
      result = Query_fetchMore(query);
    enddo;

    Query_free(query);
    SQLJob_close(job);
  on-error;
    err = MP_getLastError();
    say('Failed: ' + err.error);
  endmon;

  // releases the job and anything it still owns
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

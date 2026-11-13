# mapepire-rpg

> [!WARNING]
> **This project is experimental.** It is not an official Mapepire client
> and has had limited testing (one IBM i 7.5 system). The API may change
> without notice. Do not rely on it for production workloads yet.

A native ILE RPG client for [Mapepire](https://mapepire-ibmi.github.io/), the
WebSocket based database server for IBM i. With it, RPG programs can run SQL
and CL against any IBM i that runs `mapepire-server`, whether that is the local
system or a remote one, without using DRDA or RDB directory entries.

The client is a single service program (`MAPEPIRE`) with no dependencies
beyond the operating system. It implements everything itself: TCP sockets,
TLS through GSKit, the WebSocket protocol (RFC 6455), and JSON. It follows the
[Mapepire client reference architecture](https://mapepire-ibmi.github.io/reference/maintenance/referencearchitecture/)
and the [Mapepire protocol](https://github.com/Mapepire-IBMi/mapepire-protocol/blob/main/PROTOCOL.md).

```rpgle
dcl-s job    like(MP_SQLJob_h);
dcl-s result like(MP_QueryResult_h);
dcl-ds server likeds(MP_DaemonServer_t) inz(*likeds);

server.host = 'myibmi.example.com';
server.user = 'MYUSER';
server.password = password;
server.caFile = '/home/myuser/mapepire.pem';   // the server's certificate

job = SQLJob_new();
SQLJob_connect(job : server);

result = SQLJob_queryAndRun(job : 'select * from qiws.qcustcdt');
for row = 1 to QueryResult_getRowCount(result);
  dsply QueryResult_getValueByName(result : row : 'LSTNAM');
endfor;
QueryResult_free(result);

SQLJob_free(job);     // closes the connection, releases everything
```

## Requirements

* IBM i with a current ILE RPG compiler. Built and tested on 7.5; 7.4
  should also work, but that hasn't been tried. The code uses fully free-form
  RPG, `CCSID(*UTF8)` fields, `%PARMNUM`, and `ALLOC(*TERASPACE)`.
* A running `mapepire-server`, default port 8076.
* To build from source:
  [TOBi](https://ibm.github.io/ibmi-tobi/) (`makei`), installed with
  `yum install tobi`. Tested with TOBi 3.3.0.

## Building

The project is built with TOBi. `iproj.json` marks the project root, and the
`Rules.mk` file in each source directory lists the objects that directory
builds. The object library is the TOBi variable `MAPEPIRE_LIB`.

Clone the repository into the IFS, then build from its root in PASE:

```sh
export MAPEPIRE_LIB=MYLIB
makei build                        # everything: client, tests, examples
makei build -t MAPEPIRE.BNDDIR     # only the client
makei compile -f mpjson.rpgle      # one source file
```

TOBi rebuilds only what changed. The compile listings and job logs go to
`.logs/`. The library must already exist (`CRTLIB MYLIB`).

| Object | Type | Source | Contents |
|---|---|---|---|
| `MPUTIL` `MPTRANS` `MPWS` `MPJSON` `MPSQLJOB` `MPQUERY` | `*MODULE` | `qrpglesrc/*.rpgle` | the client's modules |
| `MAPEPIRE` | `*SRVPGM` | `qsrvsrc/mapepire.bnd` | the client (`ACTGRP(*CALLER)`) |
| `MAPEPIRE` | `*BNDDIR` | `qsrvsrc/mapepire.bnddir` | binding directory that contains the service program |
| `MPTEST` | `*PGM` | `qtestsrc/mptest.rpgle` | integration tests |
| `MPEXQUERY` `MPEXPARMS` | `*PGM` | `examples/*.rpgle` | examples |

To use the client in a program, include the copybook and bind with the binding
directory:

```rpgle
ctl-opt bnddir('MYLIB/MAPEPIRE');
/copy qrpgleref/mapepire.rpgleinc
```

TOBi binds the test and example programs to `MAPEPIRE` through the library
list, so `MYLIB` must be in the library list when they run.

## Mapping to the reference architecture

RPG has no classes. The client follows the two object-oriented pillars that
RPG supports well, as described in
[*Guru: Procedure Driven RPG And Adopting The Pillars Of Object-Oriented Programming*](https://www.itjungle.com/2024/02/19/guru-procedure-driven-rpg-and-adopting-the-pillars-of-object-oriented-programming/):

* **Encapsulation.** `SQLJob`, `Query`, `QueryResult` and `Params` are opaque
  handles. Their layouts live only in the service program (`mpobj.rpgleinc`),
  and only the public procedures are exported (`qsrvsrc/mapepire.bnd`). Every
  object starts with an eye-catcher, so a stale or bogus handle is rejected
  with an exception instead of corrupting storage.
* **Inheritance.** This is done through `LIKEDS` composition. Internally,
  `SQLJob_t` embeds `BaseJob_t`, as the Python `SQLJob` extends `BaseJob`.
  Publicly, every response data structure embeds `MP_ServerResponse_t` as
  `base`, so the common fields are always `x.base.success`, `x.base.error`,
  and so on.

| Reference architecture | RPG |
|---|---|
| `SQLJob(options)` | `SQLJob_new(MP_JobOptions_t)` |
| `job.connect(DaemonServer)` | `SQLJob_connect(job : MP_DaemonServer_t)` returns `MP_ConnectionResult_t` |
| `job.query(sql, QueryOptions)` | `SQLJob_query(job : sql : MP_QueryOptions_t)` |
| `job.query_and_run(sql, opts)` | `SQLJob_queryAndRun(job : sql : opts : rows)` |
| `job.get_status()` / `JobStatus` | `SQLJob_getStatus(job)` / `MP_JOB_NOT_STARTED`, `MP_JOB_READY`, `MP_JOB_BUSY`, `MP_JOB_ENDED` |
| `job._get_unique_id(prefix)` | `SQLJob_getUniqueId(job : prefix)` |
| `job.close()` / `__exit__` | `SQLJob_close(job)` / `SQLJob_free(job)` |
| `query.run(rows_to_fetch)` | `Query_run(query : rows)` (default 100 rows) |
| `query.fetch_more(rows)` | `Query_fetchMore(query : rows)` |
| `query.close()` | `Query_close(query)` / `Query_free(query)` |
| `query.state` / `QueryState` | `Query_getState(query)` / `MP_QUERY_NOT_YET_RUN`, `MP_QUERY_RUN_MORE_DATA_AVAIL`, `MP_QUERY_RUN_DONE`, `MP_QUERY_ERROR` |
| response dict | `QueryResult_*` accessors on the result handle |
| `QueryOptions.parameters` (list) | a `Params` object: `Params_new`, `Params_addString`, `Params_addInt`, ... |

The client also covers protocol messages that the Python reference does not
wrap:

* `SQLJob_ping` (`ping`)
* `SQLJob_getVersion` (`getversion`)
* `SQLJob_getDbJob` (`getdbjob`)
* `SQLJob_explain` (`dove`, Visual Explain)
* `Query_execute` (`execute`: run a prepared statement again with new values)
* batch execution, through `Params_newRow`

It does not cover `setconfig` and `gettracedata` (server tracing), or
connection pools.

## Connecting and TLS

Declare `MP_DaemonServer_t` with `INZ(*LIKEDS)` to pick up the defaults
(port 8076, TLS on). The server certificate is checked in one of three ways:

| Setting | Verification |
|---|---|
| default (`ca` and `caFile` empty) | Full validation against the **\*SYSTEM** certificate store (DCM), plus host name verification against the certificate's DNS names. |
| `ca` (PEM text) or `caFile` (IFS path to a PEM file) | **Certificate pinning.** The server must present exactly this certificate. Use this with Mapepire's default self-signed certificate. |
| `ignoreUnauthorized = *on` | **No verification.** Anyone between you and the server can read your password. Only use this on throw-away test systems. |

To fetch a server's certificate for pinning, run this in PASE (or anywhere
that has OpenSSL):

```sh
openssl s_client -connect myibmi.example.com:8076 </dev/null 2>/dev/null \
  | openssl x509 > /home/myuser/mapepire.pem
```

Before you trust that file, check its fingerprint against the server
(`openssl x509 -in mapepire.pem -noout -fingerprint -sha256`).

Other connection settings:

* `useTls = *off` connects to a server started with `MP_UNSECURE=true`
  (`ws://`).
* `timeout` sets a read timeout in seconds. The default, 0, waits forever.
* `MP_JobOptions_t` holds `technique` (`tcp` or `cli`), `application`, and
  `props`. `props` takes JDBC properties, for example
  `naming=system;libraries=MYLIB,QGPL`.

## Running queries

```rpgle
dcl-ds opts likeds(MP_QueryOptions_t) inz(*likeds);
dcl-s parms like(MP_Params_h);

parms = Params_new();
Params_addString(parms : 'A01');
opts.parameters = parms;              // prepared statement

query = SQLJob_query(job : 'select * from employee where workdept = ?' : opts);
result = Query_run(query : 500);      // first 500 rows
dow *on;
  for row = 1 to QueryResult_getRowCount(result);
    name   = QueryResult_getValueByName(result : row : 'LASTNAME');
    salary = QueryResult_getDecimal(result : row : 8);
    if QueryResult_isNull(result : row : 9); ... endif;
  endfor;
  QueryResult_free(result);
  if Query_getState(query) = MP_QUERY_RUN_DONE;
    leave;
  endif;
  result = Query_fetchMore(query);
enddo;
Query_free(query);
Params_free(parms);
```

* Rows and columns are numbered from 1. Column metadata is available from
  `QueryResult_getColumn`, which returns `MP_ColumnMetaData_t`: name, label,
  type, precision, scale, nullable, and so on.
* Values come back as text. Numbers use JSON notation (`12.5`), booleans are
  `true`/`false`, and NULL is an empty string. Use `QueryResult_isNull` to tell
  NULL from an empty string. `QueryResult_getInt` and `QueryResult_getDecimal`
  convert the text for you.
* `isTerseResults = *on` asks the server for rows as arrays instead of
  objects, which makes for smaller messages.
* `isClCommand = *on` runs the text as a CL command. The result rows are the
  job log messages it produced. Like the reference client, a failing CL
  command does **not** raise an exception. Check `QueryResult_isSuccess`.
* `autoClose = *on` closes the server cursor as soon as the last block has
  been fetched.
* `QueryResult_getOutputParm(result : n)` returns the value of output
  parameter `n` of a `CALL`. OUT parameters still need a placeholder value in
  the `Params`, for example `Params_addInt(parms : 0)`. The server rejects
  `null`.
* `QueryResult_getField(result : 'name')` returns any top-level field of the
  server response.

## Errors

Like the reference implementation, failures raise an exception: escape
message **CPF9898**, with the error text as message data. This covers:

* connection, TLS, and authentication failures
* SQL errors (the query goes to `MP_QUERY_ERROR`)
* misuse, such as fetching from a finished query or passing an invalid handle

Trap the exception with `MONITOR` and get the details from
`MP_getLastError()`:

```rpgle
monitor;
  result = SQLJob_queryAndRun(job : 'select * from nosuchtable');
on-error;
  err = MP_getLastError();     // err.error, err.sqlState, err.sqlRc
endmon;
```

## Object lifetime

RPG has no garbage collector, so the ownership rules are explicit:

* A job owns its queries. A query owns its results.
* `QueryResult_free`, `Query_free`, `Params_free`, and `SQLJob_free` each
  release the object and set the handle to `*NULL`.
* `SQLJob_free` closes the connection if it is still open, and releases every
  query and result that the job still owns.
* A result from `SQLJob_queryAndRun` or `SQLJob_explain` owns its (already
  closed) query. Freeing the result releases both.
* `Params` are copied into the query when you create it, so you can free or
  reuse a `Params` object right afterwards.

## Limits

* A single value returned by a getter is truncated at `MP_VALUE_MAX` (65,535)
  characters. An SQL statement is limited to `MP_SQL_MAX` (2 MB).
* The client is synchronous. Each request waits for its response, and
  responses are matched by `id`.
* Text is converted between UTF-8 and the job CCSID. Characters that the job
  CCSID cannot represent become substitution characters. Do not run under
  CCSID 65535.

## Tests

`MPTEST` runs integration tests against a live server: 23 scenarios with 99
checks. They cover:

* connecting, ping, and version
* data types, metadata, paging, and terse results
* parameters, escaping, and Unicode round trips
* DDL and DML, batch inserts, and re-executing a prepared statement
* `CALL` output parameters, SQL errors, and CL commands
* a 5,000-row result and a 150 KB request (64-bit WebSocket frames)
* Visual Explain and invalid handles
* a wrong password, rejection of an untrusted certificate by default, and
  rejection of a different pinned certificate

The test program needs a file of `KEY=value` lines. Protect the file: it holds
a password.

```text
MAPEPIRE_HOST=myibmi.example.com
MAPEPIRE_USER=MYUSER
MAPEPIRE_PASSWORD=secret
MAPEPIRE_CA_FILE=/home/myuser/mapepire.pem
MAPEPIRE_TEST_LIB=MYLIB
MAPEPIRE_UNTRUSTED=/path/to/mapepire-rpg/qtestsrc/untrusted.pem
```

```sh
export MAPEPIRE_LIB=MYLIB
makei build -t MPTEST.PGM
qsh -c "liblist -a MYLIB; system \"CALL MYLIB/MPTEST PARM('/home/myuser/mptest.conf')\""
```

The tests create and drop the table `MPRPGTST` and the procedure `MPRPGPROC`
in `MAPEPIRE_TEST_LIB`. `qtestsrc/untrusted.pem` is a throw-away self-signed
certificate (no key) used by the "wrong pinned certificate" test.

## Source layout

```text
iproj.json                    TOBi project: object library, include path
Rules.mk                      TOBi: source directories of the project
qrpgleref/mapepire.rpgleinc   public API: copy this into your programs
qrpgleref/mpint.rpgleinc      internal: shared low-level prototypes
qrpgleref/mpobj.rpgleinc      internal: object layouts (BaseJob, SQLJob, Query, ...)
qrpglesrc/mpsqljob.rpgle      SQLJob
qrpglesrc/mpquery.rpgle       Query, QueryResult, Params
qrpglesrc/mpjson.rpgle        JSON writer and parser (UTF-8, no recursion)
qrpglesrc/mpws.rpgle          WebSocket client (RFC 6455)
qrpglesrc/mptrans.rpgle       TCP and TLS (GSKit), certificate checks
qrpglesrc/mputil.rpgle        buffers, CCSID conversion, base64, SHA-1, errors
qsrvsrc/mapepire.bnd          service program exports
qsrvsrc/mapepire.bnddir       binding directory (TOBi pseudo-source)
qtestsrc/mptest.rpgle         integration tests
examples/                     MPEXQUERY (query and paging), MPEXPARMS (parameters, batch, CL)
```

Each source directory has its own `Rules.mk`.

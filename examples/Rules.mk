# Example programs

MPEXQUERY.MODULE: private TEXT := Mapepire example: query and paging
MPEXQUERY.MODULE: mpexquery.rpgle mapepire.rpgleinc
MPEXQUERY.PGM: private TEXT := Mapepire example: query and paging
MPEXQUERY.PGM: private ACTGRP := *NEW
MPEXQUERY.PGM: MPEXQUERY.MODULE MAPEPIRE.SRVPGM

MPEXPARMS.MODULE: private TEXT := Mapepire example: parameters, batch, CL
MPEXPARMS.MODULE: mpexparms.rpgle mapepire.rpgleinc
MPEXPARMS.PGM: private TEXT := Mapepire example: parameters, batch, CL
MPEXPARMS.PGM: private ACTGRP := *NEW
MPEXPARMS.PGM: MPEXPARMS.MODULE MAPEPIRE.SRVPGM

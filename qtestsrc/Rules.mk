# Integration tests (need a running mapepire-server, see README)

MPTEST.MODULE: private TEXT := Mapepire RPG client tests
MPTEST.MODULE: mptest.rpgle mapepire.rpgleinc

MPTEST.PGM: private TEXT := Mapepire RPG client tests
MPTEST.PGM: private ACTGRP := *NEW
MPTEST.PGM: MPTEST.MODULE MAPEPIRE.SRVPGM

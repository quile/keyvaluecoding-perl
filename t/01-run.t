#!/usr/bin/env perl

use lib 't';
use lib 'lib';
use lib '../lib';


use TestKeyValueCoding;
use TestKeyValueCodingSimple;
use TestKeyValueCodingOnPlainObject;
use TestKeyValueCodingUniversal;
BEGIN {
    eval { require Moose };
    unless ($@) {
        eval "use TestKeyValueCodingOnMooseObject";
        print STDERR "Detected Moose, loading...\n";
    }
    eval { require Moo };
    unless ($@) {
        eval "use TestKeyValueCodingOnMooObject";
        print STDERR "Detected Moo, loading...\n";
    }
    eval { require Mouse };
    unless ($@) {
        eval "use TestKeyValueCodingOnMouseObject";
        print STDERR "Detected Mouse, loading...\n";
    }
}

Test::Class->runtests;
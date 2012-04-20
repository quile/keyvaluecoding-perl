#!/usr/bin/env perl

use TestKeyValueCoding;
use TestKeyValueCodingOnObject;
BEGIN {
    my $hasMoose = eval { require Moose };
    unless ($@) {
        print STDERR "Loading Moose tests\n";
        eval "use TestKeyValueCodingOnMooseObject";
    }
}

Test::Class->runtests;
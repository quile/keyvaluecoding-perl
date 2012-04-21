#!/usr/bin/env perl

use lib 't';
use TestKeyValueCoding;
use TestKeyValueCodingOnObject;
BEGIN {
    my $hasMoose = eval { require Moose };
    unless ($@) {
        eval "use TestKeyValueCodingOnMooseObject";
    }
}

Test::Class->runtests;
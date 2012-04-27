#!/usr/bin/env perl

use lib 't';
use lib 'lib';
use lib '../lib';


use TestKeyValueCoding;
use TestKeyValueCodingOnObject;
use TestKeyValueCodingSimple;
BEGIN {
    my $hasMoose = eval { require Moose };
    unless ($@) {
        eval "use TestKeyValueCodingOnMooseObject";
    }
}

Test::Class->runtests;
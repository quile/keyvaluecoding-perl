package TestKeyValueCodingOnMooseObject;

use common::sense;

use strict;
use base qw(
    Test::Class
);

use Test::More;

sub startup : Test(startup) {
    my ( $self ) = @_;
    $self->{obj} = _PlainMooseThing->new();
    $self->{obj}->setValueForKey( "william", "shakespeare" );
}

sub test_object_properties : Tests {
    my ( $self ) = @_;
    my $obj = $self->{obj};
    $obj->bacon( "francis" );

    ok( $obj->valueForKey( "shakespeare" ) eq "william", "Moose: william shakespeare" );
    ok( $obj->valueForKey( "marlowe" ) eq "christopher", "Moose: christopher marlowe" );
    ok( $obj->valueForKey( "bacon" ) eq "francis", "Moose: francis bacon" );

    ok( $obj->valueForKey( "_s('donne')" ) eq "DONNE", "Moose: john donne" );
    ok( $obj->valueForKey( "donne.john" ) eq "jonny", "Moose: jonny" );
    ok( $obj->valueForKey( "_s(donne.john)" ) eq "JONNY", "Moose: JONNY" );
}


package _PlainMooseThing;

use common::sense;

use Moose;
use base 'Object::KeyValueCoding';

has bacon       => ( is => "rw", isa => "Str", );
has shakespeare => ( is => "rw", isa => "Str", );

sub marlowe { return "christopher" }
sub chaucer {
    my ( $self, $value ) = @_;
    if ( $value eq "geoffrey" ) { return "canterbury" }
    return "tales";
}

sub _s {
    my ( $self, $value ) = @_;
    return uc($value);
}

sub donne {
    return {
        "john" => 'jonny',
        "bruce" => 'brucey'
    };
}

1;



1;
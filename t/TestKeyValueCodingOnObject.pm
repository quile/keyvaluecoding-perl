package TestKeyValueCodingOnObject;

use strict;

use base qw(
    Test::Class
);

use Test::More;

sub setUp : Test(startup) {
    my ( $self ) = @_;
    $self->{obj} = _ObjectTestThing->new();
    $self->{obj}->setValueForKey( "william", "shakespeare" );
}

sub test_object_properties : Tests {
    my ( $self ) = @_;
    my $obj = $self->{obj};
    $obj->setBacon( "francis" );

    ok( $obj->valueForKey( "shakespeare" ) eq "william", "william shakespeare" );
    ok( $obj->valueForKey( "marlowe" ) eq "christopher", "christopher marlowe" );
    ok( $obj->valueForKey( "bacon" ) eq "francis", "francis bacon" );

    ok( $obj->valueForKey( "_s('donne')" ) eq "DONNE", "john donne" );
    ok( $obj->valueForKey( "donne.john" ) eq "jonny", "jonny" );
    ok( $obj->valueForKey( "_s(donne.john)" ) eq "JONNY", "JONNY" );
}

sub test_additions : Tests {
    my ( $self ) = @_;
    my $obj = $self->{obj};
    $DB::single = 1;
    is_deeply( $obj->valueForKey( "sorted(taylorColeridge)" ), [ "kublai khan", "samuel", "xanadu" ], "sorted" );
    is_deeply( $obj->valueForKey( "reversed(sorted(taylorColeridge))" ), [ "xanadu", "samuel", "kublai khan" ], "reversed" );
    is_deeply( $obj->valueForKey( "sorted(keys(donne))" ), [ "bruce", "john" ], "sorted keys" );
}

package _ObjectTestThing;

use Object::KeyValueCoding additions => 1;

sub new {
    my ( $class ) = @_;
    return bless {
        bacon => undef,
    }, $class;
}

sub shakespeare    { return $_[0]->{shakespeare} }
sub setShakespeare { $_[0]->{shakespeare} = $_[1] }

sub marlowe { return "christopher" }
sub chaucer {
    my ( $self, $value ) = @_;
    if ( $value eq "geoffrey" ) { return "canterbury" }
    return "tales";
}

sub bacon    { return $_[0]->{bacon} }
sub setBacon { $_[0]->{bacon} = $_[1] }

sub taylorColeridge { return [ "samuel", "xanadu", "kublai khan" ] }

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
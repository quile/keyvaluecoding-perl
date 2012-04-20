package TestKeyValueCodingOnObject;

use strict;

use base qw(
    Test::Class
);

use Test::More;

sub setUp : Test(startup) {
    my ( $self ) = @_;
    $self->{obj} = _TestThing->new();
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

#
# sub test_array : Tests {
#     var a = [];
#     a[0] = [CPDictionary dictionaryWithJSObject:{ 'wordsworth': 'william', 'keats': ['phil', 'bruce', 'andy', 'john'] }];
#     a[1] = ["samuel", "pepys", [ 1633, 1703 ]];
#
#     [self assert:[a valueForKey:"@0.wordsworth"] equals:"william"];
#     [self assert:[a valueForKey:"@0.keats.@3"] equals:"john"];
#     [self assert:[a valueForKey:"@1.@2.@0"] equals:1633];
#     [self assert:[a valueForKey:"@0.keats.#"] equals:4];
#     [self assert:[a valueForKey:"@1.@2.#"] equals:2];
# }


package _TestThing;

use base qw( Object::KeyValueCoding );

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
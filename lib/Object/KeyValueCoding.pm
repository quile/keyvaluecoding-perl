package Object::KeyValueCoding;

our $VERSION = "0.1";

use strict;
use Carp         qw( croak   );
use Scalar::Util qw( reftype );

sub import {
    my $class = shift;
    my $options = { @_ };
    if ( $options->{cache_keys} ) {
        Object::KeyValueCoding::Key->enableCache();
    }
}

sub setValueForKey {
    my ( $self, $value, $key ) = @_;

    if ($key =~ /\.|\(/o) {
        return $self->setValueForKeyPath($value, $key);
    }

    foreach my $setMethodName (@{ $self->setterKeyList() }) {
        if ($self->can($setMethodName)) {
            return $self->$setMethodName($value);
        }
    }

    $self->{$key} = $value;
}

sub valueForKey {
    my ( $self, $key ) = @_;

    if ($key =~ /\.|\(/o) {
        return $self->valueForKeyPath($key);
    }

    # generate get method names:
    my $keyList = $self->accessorKeyList($key);

    foreach my $testKey (@$keyList) {
        my $getMethodName = $testKey;

        if ($self->can($getMethodName)) {
            my $value = $self->$getMethodName();
            return $value;
        }
    }
    if (exists $self->{$key}) {
        return $self->{$key};
    }

    return undef;
}

sub valueForKeyPath {
    my ( $self, $keyPath ) = @_;

    my ($currentObject, $targetKeyPathElement) = $self->targetObjectAndKeyForKeyPath($keyPath);
    if ($currentObject && $targetKeyPathElement) {
        return _valueForKeyPathElementOnObject($targetKeyPathElement, $currentObject);
    }
    return undef;
}

sub setValueForKeyPath {
    my ( $self, $value, $keyPath ) = @_;

    my ($currentObject, $targetKeyPathElement) = $self->targetObjectAndKeyForKeyPath($keyPath);
    if ($currentObject && $targetKeyPathElement) {
        _setValueForKeyOnObject($value, $targetKeyPathElement->{key}, $currentObject);
    }
}


# This is very private, static API that nobody should use except me!
sub _valueForKeyPathElementOnObject {
    my ( $keyPathElement, $object ) = @_;
    my $key = $keyPathElement->{key};
    unless ( $keyPathElement->{arguments} ) {
        return _valueForKeyOnObject( $key, $object );
    }

    return undef unless ref ($object);
    if ( $object->can( $key ) ) {
        return $object->$key(@{ $keyPathElement->{argumentValues} });
    }
    if ( $key eq "valueForKey" ) {
        return _valueForKeyOnObject( $keyPathElement->{argumentValues}->[0], $object );
    }
    return _valueForKeyOnObject( $key, $object );
}

sub _valueForKeyOnObject {
    my ( $key, $object ) = @_;

    return undef unless ref ($object);
    if (UNIVERSAL::can($object, "valueForKey")) {
        return $object->valueForKey($key);
    }
    if (__isHash($object)) {
        my $keyList = Object::KeyValueCoding->accessorKeyList($key);
        foreach my $testKey (@$keyList) {
            if (exists $object->{$key}) {
                return $object->{$key};
            }
        }
        return undef;
    }
    if (__isArray($object)) {
        if ($key eq "#") {
            return scalar @$object;
        }
        if ($key =~ /^\@([0-9]+)$/) {
            my $element = $1;
            return $object->[$element];
        }
        # enhancement 2004-05-18 as part of the asset matching system
        if ($key =~ /^[a-zA-Z0-9_]+$/o) {
            my $values = [];
            foreach my $item (@$object) {
                push (@$values, _valueForKeyOnObject($key, $item));
            }
            return $values;
        }
    }
    return undef;
}

sub _setValueForKeyOnObject {
    my ( $value, $key, $object ) = @_;
    return undef unless ref ($object);
    if (UNIVERSAL::can($object, "setValueForKey")) {
        $object->setValueForKey($value, $key);
        return;
    }
    if (__isHash($object)) {
        $object->{$key} = $value;
        return;
    }
    if (__isArray($object)) {
        if ($key =~ /^\@([0-9]+)$/) {
            my $element = $1;
            $object->[$element] = $value;
            return
        }
        # enhancement 2004-05-18 as part of the asset matching system
        if ($key =~ /^[a-zA-Z0-9_]+$/o) {
            my $values = [];
            foreach my $item (@$object) {
                _setValueForKeyOnObject($value, $key, $item);
            }
        }
    }
}

# This returns the *second-to-last* object in the keypath
sub targetObjectAndKeyForKeyPath {
    my ( $self, $keyPath ) = @_;

    my $keyPathElements = keyPathElementsForPath($keyPath);

    # first evaluate any args
    foreach my $element (@$keyPathElements) {
        next unless ($element->{arguments});
        my $argumentValues = [];
        foreach my $argument (@{$element->{arguments}}) {
            if (__expressionIsKeyPath($argument)) {
                push (@$argumentValues, $self->valueForKey($argument));
            } else {
                push (@$argumentValues, $self->evaluateExpression($argument));
            }
        }
        $element->{argumentValues} = $argumentValues;
    }

    my $currentObject = $self;

    for (my $keyPathIndex = 0; $keyPathIndex < $#$keyPathElements; $keyPathIndex++) {
        my $keyPathElement = $keyPathElements->[$keyPathIndex];
        my $keyPathValue = _valueForKeyPathElementOnObject($keyPathElement, $currentObject);
        if (ref $keyPathValue) {
            $currentObject = $keyPathValue;
        } else {
            return (undef, undef);
        }
    }
    return ($currentObject, $keyPathElements->[$#$keyPathElements]);
}

# TODO: will flesh this out later
sub accessorKeyList {
    my ( $class, $key ) = @_;
    my $name = Object::KeyValueCoding::Key->new( $key );
    return [
        $key,
        $name->asCamelCaseProperty(),
        $name->asUnderscoreyProperty(),
        $name->asCamelCaseGetter(),
        $name->asUnderscoreyGetter(),
    ];
}

sub setterKeyList {
    my ( $class, $key ) = @_;
    my $name = Object::KeyValueCoding::Key->new( $key );
    return [
        $name->asCamelCaseSetter(),
        $name->asUnderscoreySetter(),
        $name->asCamelCase(),
        $name->asUnderscorey(),
        $key,
    ];
}

sub camelCase {
    my ( $name ) = @_;

    if ($name =~ /^[A-Z0-9_]+$/o) {
        return lcfirst(join("", map {ucfirst(lc($_))} split('_', $name)));
    }
    return $name;
}

# It's easier to do it this way than to import Text::Balanced
sub extractDelimitedChunkTerminatedBy {
    my ( $chunk, $terminator ) = @_;
    my $extracted = "";
    my $balanced = {};
    my $isQuoting = 0;
    my $outerQuoteChar = '';

    my @chars = split(//, $chunk);
    for (my $i = 0; $i <= $#chars; $i++) {
        my $charAt = $chars[$i];

        if ($charAt eq '\\') {
            $extracted .= $chars[$i].$chars[$i+1];
            $i++;
            next;
        }
        if ($charAt eq $terminator) {
            if (isBalanced($balanced)) {
                return $extracted;
            }
        }

        unless ($isQuoting) {
            if ($charAt =~ /["']/) { #'"
                $isQuoting = 1;
                $outerQuoteChar = $charAt;
                $balanced->{$charAt} ++;
            } elsif ($charAt =~ /[\[\{\(]/ ) {
                $balanced->{$charAt} ++;
            } elsif ($charAt eq ']') {
                $balanced->{'['} --;
            } elsif ($charAt eq '}') {
                $balanced->{'{'} --;
            } elsif ($charAt eq ')') {
                $balanced->{'('} --;
            }
        } else {
            if ($charAt eq $outerQuoteChar) {
                $isQuoting = 0;
                $outerQuoteChar = '';
                $balanced->{$charAt} ++;
            }
        }

        $extracted .= $charAt;
    }
    if (isBalanced($balanced)) {
        return $extracted;
    } else {
        # explode?
        croak "oh bugger - Error parsing keypath $chunk; unbalanced '".unbalanced($balanced)."'";
    }
    return "";
}

sub isBalanced {
    my ( $balanced ) = @_;
    foreach my $char (keys %$balanced) {
        return 0 if ($char =~ /[\[\{\(]/ && $balanced->{$char} != 0);
        return 0 if ($char =~ /["']/ && $balanced->{$char} % 2 != 0); #'"
    }
    return 1;
}

sub unbalanced {
    my ( $balanced ) = @_;
    foreach my $char (keys %$balanced) {
        return $char if ($char =~ /[\[\{\(]/ && $balanced->{$char} != 0);
        return $char if ($char =~ /["']/ && $balanced->{$char} % 2 != 0); #'"
    }
}

sub keyPathElementsForPath {
    my ( $path ) = @_;

    return [ map { {key => $_} } split(/\./, $path)] unless ($path =~ /[\(\)]/);

    my $keyPathElements = [];
    while (1) {
        my ($firstElement, $rest) = split(/\./, $path, 2);
        $firstElement ||= "";
        $rest ||= "";
        if ($firstElement =~ /([a-zA-Z0-9_\@]+)\(/) {
            my $key = $1;
            my $element = quotemeta($key."(");
            $path =~ s/$element//;
            my $argumentString = extractDelimitedChunkTerminatedBy($path, ')');
            my $quotedArguments = quotemeta($argumentString.")")."\.?";
            # extract arguments:
            my $arguments = [];
            while (1) {
                my $argument = extractDelimitedChunkTerminatedBy($argumentString, ",");
                last unless $argument;
                push (@$arguments, $argument);
                my $quotedArgument = quotemeta($argument).",?\\s*";
                $argumentString =~ s/$quotedArgument//;
            }
            push (@$keyPathElements, { key => $key, arguments => $arguments });
            $path =~ s/$quotedArguments//;
        } else {
            push (@$keyPathElements, { key => $firstElement }) if $firstElement;
            $path = $rest;
        }
        last unless $rest;
    }
    return $keyPathElements;
}

sub evaluateExpression {
    my ( $self, $expression ) = @_;
    return eval $expression;
}

# convenience methods for key-value coding.  objects that
# implement kv coding get these methods for free but will
# probably have to override them.  They can be used in keypaths.

sub int {
    my ( $self, $value ) = @_;
    return int($value);
}

sub length {
    my ( $self, $value ) = @_;
    if (__isArray($value)) {
        return scalar @$value;
    }
    return length($value);
}

sub keys {
    my ( $self, $value ) = @_;
    if (__isHash($value)) {
        return [keys %$value];
    }
    return [];
}

sub reversed {
    my ( $self, $list ) = @_;
    return [reverse @$list];
}

sub sorted {
    my ( $self, $list ) = @_;
    return [sort @$list];
}

sub truncateStringToLength {
    my ( $self, $value, $length ) = @_;
    # this is a cheesy truncator
    if (CORE::length($value) > $length) {
        return substr($value, 0, $length)."...";
    }
    return $value;
}

sub sortedListByKey {
    my ( $self, $list, $key, $direction ) = @_;

    return [] unless scalar @$list;
    if (UNIVERSAL::can($list->[0], "valueForKey")) {
        return [sort {$a->valueForKey($key) cmp $b->valueForKey($key)} @$list];
    } elsif (__isHash($list->[0])) {
        return [sort {$a->{$key} cmp $b->{$key}} @$list];
    } else {
        return [sort @$list];
    }
}

sub alphabeticalListByKey {
    my ( $self, $list, $key, $direction ) = @_;

    return [] unless scalar @$list;
    if (UNIVERSAL::can($list->[0], "valueForKey")) {
        return [sort {ucfirst($a->valueForKey($key)) cmp ucfirst($b->valueForKey($key))} @$list];
    } elsif (__isHash($list->[0])) {
        return [sort {ucfirst($a->{$key}) cmp ucfirst($b->{$key})} @$list];
    } else {
        return [sort {ucfirst($a) cmp ucfirst($b)} @$list];
    }
}

sub commaSeparatedList {
    my ( $self, $list ) = @_;
    return $self->stringsJoinedByString($list, ", ");
}

sub stringsJoinedByString {
    my ( $self, $strings, $string ) = @_;
    return "" unless (__isArray($strings));
    return join($string, @$strings);
}

# these are useful for building expressions:

sub or {
    my ( $self, $a, $b ) = @_;
    return ($a || $b);
}

sub and {
    my ( $self, $a, $b ) = @_;
    return ($a && $b);
}

sub not {
    my ( $self, $a ) = @_;
    return !$a;
}

sub eq {
    my ( $self, $a, $b ) = @_;
    return ($a eq $b);
}

# hmm?
sub self {
    my ( $self ) = @_;
    return $self;
}

# Stole this from Craig's tagAttribute code.  It takes a string template
# like "foo fah fum ${twiddle.blah.zap} tiddly pom" and a language (which
# you can use in your evaluations) and returns the string with the
# resolved keypaths interpolated.
sub stringWithEvaluatedKeyPathsInLanguage {
    my ( $self, $string, $language ) = @_;
    return "" unless $string;
    my $count = 0;
    while ($string =~ /\$\{([^}]+)\}/g) {
        my $keyValuePath = $1;
        my $value = "";

        if (__expressionIsKeyPath($keyValuePath)) {
            $value = $self->valueForKeyPath($keyValuePath);
        } else {
            $value = eval "$keyValuePath"; # yikes, dangerous!
        }

        #\Q and \E makes the regex ignore the inbetween values if they have regex special items which we probably will for the dots (.).
        $string =~ s/\$\{\Q$keyValuePath\E\}/$value/g;
        #Avoiding the infinite loop...just in case
        last if $count++ > 100; # yikes!
    }
    return $string;
}


sub __isArray {
    my ( $object ) = @_;
    return reftype($object) eq "ARRAY";
}

sub __isHash {
    my ( $object ) = @_;
    return reftype($object) eq "HASH";
}

sub __expressionIsKeyPath {
    my $expression = shift;
    return 1 if ( $expression =~ /^[A-Za-z_\(\)]+[A-Za-z0-9_#\@\.\(\)\"]*$/o );
    return ( $expression =~ /^[A-Za-z_\(\)]+[A-Za-z0-9_#\@]*(\(|\.)/o );
}

package Object::KeyValueCoding::Key;

my $_KEY_CACHE = undef;

sub enableCache {
    $_KEY_CACHE = {};
}

sub flushCache {
    if ( $_KEY_CACHE ) {
        $_KEY_CACHE = {};
    }
}

sub disableCache {
    undef $_KEY_CACHE;
}

sub new {
    my ( $class, $key ) = @_;
    $key ||= "";
    if ( $_KEY_CACHE && $key && exists $_KEY_CACHE->{$key} ) {
        return $_KEY_CACHE->{$key};
    }

    my $parts = __normalise( $key );

    my ( $leadingUnderscores ) = $key =~ /^(_+)/;
    my ( $trailingUnderscores ) = $key =~ /(_+)$/;
    my $self = bless {
        parts => $parts,
        leadingUnderscores => $leadingUnderscores || "",
        trailingUnderscores => $trailingUnderscores || "",
    }, $class;
    if ( $_KEY_CACHE ) {
        $_KEY_CACHE->{$key} = $self;
    }
    return $self;
}

sub __normalise {
    my ( $key ) = @_;

    # $key can be
    # 1. constant format LIKE_THIS
    # 2. camel case format likeThis
    # 3. capital camel case format LikeThis
    # 4. underscorey like_this

    my $bits = [];
    $key =~ s/^_+//g;

    if ( $key =~ /[A-Za-z0-9]_[A-Za-z0-9]/ ) {
        $bits = [ split(/_+/, $key) ];
        $bits = [ map { lc } @$bits ];
    } else {
        my $new = $key;
        $new =~ s/((^[a-z]+)|([0-9]+)|([A-Z]{1}[a-z]+)|([A-Z]+(?=([A-Z][a-z])|($)|([0-9]))))/$1 /g;
        $bits = [ map { $_ =~ /^[A-Z]+$/ ? $_ : lc($_) } split(/\s+/, $new) ];
    }
    return $bits;
}

sub __camelCase {
    my ( $parts ) = @_;
    $parts ||= [];
    if ( $parts->[0] =~ /^[A-Z0-9]+$/ ) {
        return __titleCase( $parts );
    }
    return lcfirst(__titleCase( $parts ));
}

sub __constant {
    my ( $parts ) = @_;
    return join("_", map { uc } @$parts );
}

sub __titleCase {
    my ( $parts ) = @_;
    return join("", map { ucfirst } @$parts);
}

sub __underscorey {
    my ( $parts ) = @_;
    return join("_", @$parts );
}

sub asCamelCase   {   __camelCase( $_[0]->{parts} ) }
sub asConstant    {    __constant( $_[0]->{parts} ) }
sub asTitleCase   {   __titleCase( $_[0]->{parts} ) }
sub asUnderscorey { __underscorey( $_[0]->{parts} ) }

sub asCamelCaseProperty   { sprintf( "%s%s%s", $_[0]->{leadingUnderscores}, $_[0]->asCamelCase(),   $_[0]->{trailingUnderscores} ) };
sub asTitleCaseProperty   { sprintf( "%s%s%s", $_[0]->{leadingUnderscores}, $_[0]->asTitleCase(),   $_[0]->{trailingUnderscores} ) };
sub asConstantProperty    { sprintf( "%s%s%s", $_[0]->{leadingUnderscores}, $_[0]->asConstant(),    $_[0]->{trailingUnderscores} ) };
sub asUnderscoreyProperty { sprintf( "%s%s%s", $_[0]->{leadingUnderscores}, $_[0]->asUnderscorey(), $_[0]->{trailingUnderscores} ) };

sub asCamelCaseSetter   { sprintf( "%sset%s%s",  $_[0]->{leadingUnderscores}, $_[0]->asTitleCase(),   $_[0]->{trailingUnderscores} ) };
sub asTitleCaseSetter   { sprintf( "%sset%s%s",  $_[0]->{leadingUnderscores}, $_[0]->asTitleCase(),   $_[0]->{trailingUnderscores} ) };
sub asConstantSetter    { sprintf( "%sset_%s%s", $_[0]->{leadingUnderscores}, $_[0]->asConstant(),    $_[0]->{trailingUnderscores} ) };
sub asUnderscoreySetter { sprintf( "%sset_%s%s", $_[0]->{leadingUnderscores}, $_[0]->asUnderscorey(), $_[0]->{trailingUnderscores} ) };

sub asCamelCaseGetter   { sprintf( "%sget%s%s",  $_[0]->{leadingUnderscores}, $_[0]->asTitleCase(),   $_[0]->{trailingUnderscores} ) };
sub asTitleCaseGetter   { sprintf( "%sget%s%s",  $_[0]->{leadingUnderscores}, $_[0]->asTitleCase(),   $_[0]->{trailingUnderscores} ) };
sub asConstantGetter    { sprintf( "%sget_%s%s", $_[0]->{leadingUnderscores}, $_[0]->asConstant(),    $_[0]->{trailingUnderscores} ) };
sub asUnderscoreyGetter { sprintf( "%sget_%s%s", $_[0]->{leadingUnderscores}, $_[0]->asUnderscorey(), $_[0]->{trailingUnderscores} ) };


1;

__END__

=head1 NAME

Object::KeyValueCoding - Perl implementation of Key-Value Coding

=head1 SYNOPSIS

 use Object::KeyValueCoding;

 package Foo;
 use base qw( Bar Object::KeyValueCoding );

 ...

 my $o = Foo->new();
 $o->setBar("quux");
 ...
 print $o->valueForKey("bar");
 quux

See more complex examples below.


=head1 VERSION

    0.2


=head1 FEATURES

=over

=item * Easy to add to your project

Just mix it into your @ISA somehow.

=item * Production-tested

Ran on a high-volume website for 10 years.

=item * Familiar format to iOS/OSX/WebObjects developers

The basic API is really similar to NSKeyValueCoding.

=item * Almost entirely dependency-free.

Not going to bloat your project.

=back


=head1 DESCRIPTION

One of the greatest things about developing using the NeXT/Apple toolchain
is the consistent use of something called key-value coding.  It's the kind
of thing that, once you buy into its philosophy, will suddenly make a whole
slew of things easier for you in ways that you never thought of before.
Every time I move to a new platform, be it Python or Javascript or Perl,
I always find myself frustrated by its absence, and find myself jumping
through all kinds of stupid hoops just to do things that would be dead-simple
if key-value coding were available to me.

So here is a Perl implementation of KVC that you can
glom onto your objects, or even glom onto everything in your system,
and KVC will be available in all its glory (well, some of its glory...
see below).



=head1 METHODS

All implementations of KVC must support these methods:

 valueForKey( <key> )
 valueForKeyPath( <keypath> )
 setValueForKey( <value>, <key> )
 setValueForKeyPath( <value>, <keypath> )


Any KVC-aware objects will now response to those methods.
( Note: the difference between a key-path and a key is that a key-path can
be an arbitrarily long dot-path of keys ).

Here is an example session that should show how it works:

 > re.pl
 $ package Foo;
   use base qw( Object::KeyValueCoding );
   sub new { return bless $_[1] }
 $ my $foo = Foo->new({ bar => "This is foo.bar",
                        baz => { quux => "This is foo.baz.quux",
                        bonk => [ 'This is foo.baz.bonk.@0', 'This is foo.baz.bonk.@1' ]
                    }});
 Foo=HASH(0x1020576c0);
 $ $foo->valueForKey("bar")
 This is foo.bar
 $ $foo->valueForKeyPath("baz.quux")
 This is foo.baz.quux
 $ $foo->valueForKeyPath('baz.bonk.@1')
 This is foo.baz.bonk.@1
 $

If a function is found rather than a property, it will
be called in the context of the object it belongs to:


 sub Foo::bing {
     return [ 'This is foo.bing.@0', 'and this is foo.bing.@1' ];
 }
 $ $foo->valueForKey('bing.@1')
 'and this is foo.bing.@1'
 $


The implementation allows nested key-paths, which are turned into arguments:


 $ sub Foo::bong { my ($self, $bung) = @_; return uc($bung) }
 $ $foo->valueForKey("baz.quux")
 This is foo.baz.quux
 $ $foo->valueForKey("bong(baz.quux)")
 THIS IS FOO.BAZ.QUUX
 $ $foo->valueForKey("self.bong(self.baz.quux)")
 THIS IS FOO.BAZ.QUUX
 $

 See how it traverses the object graph from one related object to
 another:

 $ package Goo; use base qw( Object::KeyValueCoding ); sub new { bless $_[1] }
 $ my $goo = Goo->new({ something => $foo, name => "I'm called Goo!" });
 Goo=HASH(0x1020763d8);
 $ $goo->valueForKey("something.bong(name)")
 I'M CALLED GOO!
 $ $goo->valueForKey("something.bong(self.name)")
 I'M CALLED GOO!
 $ $goo->valueForKey("self.something.bong(self.name)")
 I'M CALLED GOO!
 $


The corresponding C<set> methods, C<setValueForKey> and C<setValueForKeyPath>
will set the value on whatever object the key/keypath resolves to.
If any part of the key or keypath returns *null*, the call will
(at present) fail silently.  B<NOTE:> This is not the same behaviour
as Apple's NSKeyValueCoding; it's a bit more like the Clojure
"thread" operator (->>).


=head1 EXTRA STUFF

The implementation has some optional "additions" that you can use.
What are these "additions"?  They provide a number of "special" methods
that can be used in keypaths:

=over

 eq(a, b)
 not( a )
 and( a, b )
 or( a, b )
 commaSeparatedList( a )
 truncateStringToLength( a, l )
 sorted( a )
 reversed( a )
 keys( a )
 length( a )
 int( a )

=back

For example:

 $ my $goo = Goo->new({ a => 1, b => 0, c => 0 });
 Goo=HASH(0x1020633d0);
 $ $goo->valueForKey("and(a, b)")
 0
 $ $goo->valueForKey("or(a, b)")
 1
 $ $goo->valueForKey("or(b, c)")
 0
 $

Note that the arguments themselves can be arbitrarily long key-paths.


=head1 TODO

=over

=item * Better support for Moose

Since Moose is pretty much the defacto way now of doing OO
in Perl, KVC should detect Moose and play nicer with it.  It means
that it could use the Class::MOP features to perform attribute
manipulation, so that will be fun.

=item * Error handling

Right now you're on your own to test for errors and trap explosions.

=item * Bulletproofing

There are lots of cases that could have slipped through the cracks, so it
will need some cleaning up and bulletproofing to harden it a bit.



=back

=head1 HISTORY

This implementation originated as part of the Idealist Framework
(https://github.com/quile/if-framework) over 10 years
ago.  It was loosely based on the NSKeyValueCoding protocol found
on NeXTStep/OpenStep (at that time) and now Cocoa/iOS.  This is the
reason why the code is a bit hairy - its very old (predating pretty much
every advance in Perl...).  But that works in its favour, because it
means it will work well with most Perl objects and isn't bound to
an OO implementation like Moose.


=head1 BUGS

Please report bugs to E<lt>info[at]kyledawkins.comE<gt>.

=head1 CONTRIBUTING

The github repository is at https://quile@github.com/quile/keyvaluecoding-perl.git


=head1 SEE ALSO

Some other stuff.

=head1 AUTHOR

Kyle Dawkins, E<lt>info[at]kyledawkins.comE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright 2012 by Kyle Dawkins

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut




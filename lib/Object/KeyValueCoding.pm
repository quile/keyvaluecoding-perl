package Object::KeyValueCoding;

use common::sense;
use Carp qw( croak );

sub setValueForKey {
    my ( $self, $value, $key ) = @_;

    if ($key =~ /\.|\(/o) {
        return $self->setValueForKeyPath($value, $key);
    }

    my $setMethodName = "set".ucfirst(niceName($key));
    if ($self->can($setMethodName)) {
        return $self->$setMethodName($value);
    }

    $self->{$key} = $value;
}

sub valueForKey {
    my ( $self, $key ) = @_;

    if ($key =~ /\.|\(/o) {
        return $self->valueForKeyPath($key);
    }

    # generate get method names:
    my $keyList = listOfPossibleKeyNames($key);

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

# This is very private, static API that nobody should use except me!
sub _valueForKeyPathElementOnObject {
    my ( $keyPathElement, $object ) = @_;
    my $key = $keyPathElement->{key};
    unless ($keyPathElement->{arguments}) {
        return _valueForKeyOnObject($key, $object);
    }

    return undef unless ref ($object);
    if (UNIVERSAL::can($object, $key)) {
        return $object->$key(@{$keyPathElement->{argumentValues}});
    }
    if ($key eq "valueForKey") {
        return _valueForKeyOnObject($keyPathElement->{argumentValues}->[0], $object);
    }
    return _valueForKeyOnObject($key, $object);
}

sub _valueForKeyOnObject {
    my ( $key, $object ) = @_;

    return undef unless ref ($object);
    if (UNIVERSAL::can($object, "valueForKey")) {
        return $object->valueForKey($key);
    }
    if (__isHash($object)) {
        my $keyList = listOfPossibleKeyNames($key);
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
    return unless __isHash($object);
    $object->{$key} = $value;
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
sub listOfPossibleKeyNames {
    my ( $key ) = @_;
    my $niceName = niceName($key);
    return [$key, "_$key", $niceName, "_$niceName"];
}

sub niceName {
    my ( $name ) = @_;

    if ($name =~ /^[A-Z0-9_]+$/o) {
        return lcfirst(join("", map {ucfirst(lc($_))} split('_', $name)));
    }
    return $name;
}

sub keyNameFromNiceName {
    my ( $niceName ) = @_;

    my @pieces = split(/([A-Z0-9])/, $niceName);
    my @uppercasePieces = ();

    for (my $i=0; $i<=$#pieces; $i++) {
        next if $pieces[$i] eq "";
        if ($pieces[$i] =~ /^[a-z0-9]$/) {
            push (@uppercasePieces, uc($pieces[$i]));
        } elsif ($pieces[$i] =~ /^[A-Z0-9]$/) {
            # either it's an acronym, a single char or
            # a first char

            if ($pieces[$i+1] ne "") {
                push (@uppercasePieces, uc($pieces[$i].$pieces[$i+1]));
                $i++;
            } else {
                my $j = $i;
                # acronyms
                my $acronym = "";
                while ($pieces[$i+1] eq "" && $i <= $#pieces) {
                    $acronym .= $pieces[$i];
                    $i+=2;
                }
                push (@uppercasePieces, $acronym);
                last if $i >= $#pieces;
                $i--;
            }
        } else {
            push (@uppercasePieces, uc($pieces[$i]));
        }
    }
    my $keyName = join("_", @uppercasePieces);
    return $keyName;
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
    if (__isDictionary($value)) {
        return [keys %$value];
    }
    return [];
}

sub reverse {
    my ( $self, $list ) = @_;
    return [reverse @$list];
}

sub sort {
    my ( $self, $list ) = @_;
    return [sort @$list];
}

sub truncateStringToLength {
    my ( $self, $value, $length ) = @_;
    # this is a cheesy truncator
    if (length($value) > $length) {
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
    return UNIVERSAL::isa($object, "ARRAY");
}

sub __isHash {
    my ( $object ) = @_;
    return UNIVERSAL::isa($object, "HASH");
}

sub __expressionIsKeyPath {
    my $expression = shift;
    return 1 if ( $expression =~ /^[A-Za-z_\(\)]+[A-Za-z0-9_#\@\.\(\)\"]*$/o );
    return ( $expression =~ /^[A-Za-z_\(\)]+[A-Za-z0-9_#\@]*(\(|\.)/o );
}


1;
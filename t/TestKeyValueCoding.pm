package TestKeyValueCoding;

use common::sense;

use base qw(
    Test::Class
);

use Test::More;
use Object::KeyValueCoding;

my $camelCaseUpperCaseMap = {
    'attributeName' => "ATTRIBUTE_NAME",
    'name' => "NAME",
    'aBigLongName' => "A_BIG_LONG_NAME",
    'aProperty' => "A_PROPERTY",
};

sub test_names : Test(8) {
    my ($self) = @_;
    foreach my $key (keys %{$camelCaseUpperCaseMap}) {
        my $value = $camelCaseUpperCaseMap->{$key};
        my $valueResult = Object::KeyValueCoding::keyNameFromNiceName($key);
        my $keyResult = Object::KeyValueCoding::niceName($value);
        ok($value eq $valueResult,"keyNameFromNiceName: $key -> $value (result: $valueResult)");
        ok($key eq $keyResult,"niceName: $value -> $key (result: $keyResult)");
    }
}

my $keyPathToElementArrayMap = {
    # Commented out b/c whitespace is not stripped at the moment
    #' abc.def.ghi ' => [qw(abc def ghi)], # test stripping of whitespace
    'xyz.bbc.xyz' => [qw(xyz bbc xyz)],
    'nnn' => [qw(nnn)],
    'ooo.' => [qw(ooo)],  # hmm, this one passes
};

my $keyPathsWithArguments = {
    q(abc.def("Arg With Spaces").yyy) => [{key => 'abc'},
                                         {key => 'def', arguments => [q("Arg With Spaces")]},
                                         {key => 'yyy'}, ],
};

sub test_parsing : Test(no_plan) {
    my ($self) = @_;
    foreach my $keyPath (keys %{$keyPathToElementArrayMap}) {
        my $reference = $keyPathToElementArrayMap->{$keyPath};
        my $test = Object::KeyValueCoding::keyPathElementsForPath($keyPath);
        ok(scalar @$reference == scalar @$test, "$keyPath has correct element count");
        foreach my $i (0..scalar @$reference -1) {
            ok ($reference->[$i] eq $test->[$i]->{key}, "element matches: ".$reference->[$i]." == ".$test->[$i]->{key});
        }
    }

    foreach my $keyPath (keys %{$keyPathsWithArguments}) {
        my $reference = $keyPathsWithArguments->{$keyPath};
        my $test = Object::KeyValueCoding::keyPathElementsForPath($keyPath);
        ok(scalar @$reference == scalar @$test, "$keyPath has correct element count");
        foreach my $i (0..scalar @$reference -1) {
            ok ($reference->[$i]->{key} eq $test->[$i]->{key}, "element matches: ".$reference->[$i]->{key}." == ".$test->[$i]->{key});
            ok (defined $reference->[$i]->{arguments} == defined $test->[$i]->{arguments}, "Both either do or don't have arguments");
            if (defined $reference->[$i]->{arguments}) {
                ok (scalar @{$reference->[$i]->{arguments}} == scalar @{$test->[$i]->{arguments}}, "element has correct argument count");
                my $refArgs = $reference->[$i]->{arguments};
                my $testArgs = $test->[$i]->{arguments};
                for my $j (0..scalar @$refArgs -1) {
                    ok($refArgs->[$j] eq $testArgs->[$j], "arg $j matches: ".$refArgs->[$j]." eq ".$testArgs->[$j]);
                }
            }
        }
    }

    #my $root = _Test::Entity::Root->new();
    #$root->setTitle("Banana");
    #ok($root->stringWithEvaluatedKeyPathsInLanguage('Title: ${title}') eq "Title: Banana", "key paths in interpolated string work");
}

1;
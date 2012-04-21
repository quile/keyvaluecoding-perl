use inc::Module::Install;

name           'Object-KeyValueCoding';
all_from       'lib/Object/KeyValueCoding.pm';

# Specific dependencies
requires       'Scalar::Util';
test_requires  'Test::More'  => '0.42';

WriteAll;
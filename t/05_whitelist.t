use strict;
use warnings;
use Test::More;
use Test::LongString;
use Data::Undump qw(undump);
use Data::Dumper;

my @tests = (
  [qq{bless([],"foo")}, undef, "Object, no options"],
  [qq{bless([],"foo")}, {valid_class_names => {}}, "Object, empty whitelist", qr/foo/],
  [qq{bless([],"foo")}, {valid_class_names => {bar => undef}}, "Object, whitelist w/o foo", qr/foo/],
  [qq{bless([],"foo")}, {valid_class_names => {foo => undef}}, "Object, whitelisted class"],
);
plan tests => scalar(@tests);


foreach my $t (@tests) {
  my ($dump, $options, $name, $exception_like) = @$t;
  my $reference = eval $dump;

  my $undumped;
  my $have_exception;
  my $exception;
  eval {
    $undumped = undump($dump, $options ? ($options) : ());
    1
  } or do {
    $exception = $@;
    $have_exception = 1;
  };

  if ($have_exception) {
    note("Got exception: '$exception'");
    ok(defined($exception_like) && $exception =~ $exception_like, $name);
  }
  else {
    note("Expected exception, but got none") if defined $exception_like;
    fail($name), next if defined $exception_like;
    is_deeply($undumped, $reference, $name);
  }
}


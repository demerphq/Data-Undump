use strict;
use warnings;
use Test::More;
use Data::Undump qw(undump);
use Data::Dumper;
our @tests;
{
    local $/= "";
    while (<DATA>) {
        chomp;
        push @tests, [split /\s*\|\s*/, $_, 2];
    }
}
plan tests => 1 + @tests;
pass();
foreach my $test (@tests) {
    my ($dump, $want_error)= @$test;
    my $res= undump($dump);
    my $got_error= $@ || "";
    s/^\s+//, s/\s+\z// for $got_error;
    is( $got_error, $want_error, "code: >>$dump<<");
}

__DATA__
{ | unterminated HASH constructor

{ foo => | unterminated HASH constructor

{ foo => [ | unterminated ARRAY constructor

{ foo foo => | got a bareword where it was not expected

"foo | unterminated double quoted string

'foo | unterminated single quoted string

use strict;
use warnings;
use Test::More;
use Test::LongString;
use Data::Undump qw(undump);
use Data::Dumper;
our @dump;
{
    local $/="";
    while (<DATA>) {
        chomp;
        push @dump, $_;
    }
}
plan tests => 1 + 2 * @dump;
pass();
sub dd { return Data::Dumper->new([$_[0]])->Purity(1)->Useqq(1)->Sortkeys(1)->Dump() }
sub check {
    my $dump= shift;
    my $undumped= dd(my $struct= undump($dump));
    my $evaled= dd(eval($dump));

    $dump eq "undef"
        ? pass("undumping undef")
        : isnt($struct, undef, "undump succeeded: >>$dump<<");
    return is_string($undumped,$evaled,"undump and eval agree");
}

check($_) for @dump;
BEGIN {
    @dump= (
        " 'foo' ",
        ' "foo" ',
    );
}
__DATA__
1

0

123013.139

-1234.59

0.41

-0.13

123

''

"foo"

'foo'

undef

[]

{}

{ foo => 'bar' }

[ 1 ]

[ 1, [ 2 ] ]

[1,2,[3,4,{5=>6,7=>{8=>[]},9=>{}},{},[]]]

[ 1 , 2 , [ 3 , 4 , { 5 => 6 , 7 => { 8 => [ ] } , 9 => { } } , { }, [ ] ] ]

{
    foo => 123,
    bar => -159.23 ,
    'baz' =>"foo",
    'bop \''=> "\10"
    ,'bop \'\\'=> "\x{100}" ,
    'bop \'x\\x'    =>"x\x{100}"   , 'bing' =>   "x\x{100}",
    x=>'y', z => 'p', i=> '1', l=>" \10", m=>"\10 ", n => " \10 ",
}

{
    foo => [123],
    "bar" => [-159.23 , { 'baz' => "foo", }, ],
    'bop \''=> { "\10" => { 'bop \'\\'=> "\x{100}", h=>{
    'bop \'x\\x'    =>"x\x{100}"   , 'bing' =>   "x\x{100}",
    x=>'y',}, z => 'p' ,   }   ,  i    =>  '1' ,}, l=>" \10", m=>"\10 ", n => " \10 ",
    o => undef ,p=>undef,
}

[ "\$", "\@", "\%" ]

{ "" => '"', "'" => "" }

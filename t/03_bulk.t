use strict;
use warnings;
use Benchmark qw(cmpthese);
use Data::Dumper;
use Test::More;
use Test::LongString;
use Data::Undump qw(undump);
our $CORPUS;
BEGIN {
    $CORPUS||= $ENV{CORPUS} || "corpus";
}
sub read_files {
    my $sub= shift;
    open my $fh, "<", $CORPUS
        or die "Failed to read '$CORPUS': $!";
    local $/="\n---\n";
    $_[0]||=0;
    while (<$fh>) {
        chomp;
        $_[0]++ if $sub->($_);
    }
    close $fh;
    $_[0];
}

if (!@ARGV) {
    my $total= read_files(sub { return 1 });
    plan(tests=>$total+1);
    my $read= 0;
    my $eval_ok= read_files(sub {
        print STDERR "# read $read\n" unless ++$read % 1000;
        my $undump = undump($_[0]);
        if ($@) {
            my $ok= is($@,"Encountered variable in input. This is not eval - can not undump code\n")
                or diag("\nUndump died with error:\n$@\n$_[0]\n"); 
            return $ok;
        };
        my $VAR1;
        my $eval= eval $_[0];
        my $eval_dump= Data::Dumper->new([$eval])->Sortkeys(1)->Dump();
        my $undump_dump= Data::Dumper->new([$undump])->Sortkeys(1)->Dump();
        my $ok= is_string($undump_dump, $eval_dump)
            or diag $_[0];
        return $ok;
    });
    is($total,$eval_ok);
}
my $time= $CORPUS=~/big/ ? 5 : -1;
my $result= cmpthese $time, {
    ((0) ? ( 'read' => sub {
        read_files(sub { return 1 });
    }) : ()),
    'eval'   => sub{
        read_files(sub { my $VAR1; return eval($_[0]); })
    },
    'undump' => sub{
        read_files(sub { return undump($_[0]); })
    },
    'undump_eval' => sub{
        read_files(sub { my $VAR1; return( undump($_[0])||eval($_[0])); })
    },
};
diag join "\n","", map {sprintf"%-20s" . (" %20s" x (@$_-1)), @$_ } @$result;

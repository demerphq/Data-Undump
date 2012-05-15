package Data::Dumper::Undump;

use 5.008008;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw( undump );
our %EXPORT_TAGS = ( 'all' => \@EXPORT_OK );
our @EXPORT = qw(undump);

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Data::Dumper::Undump', $VERSION);

1;
__END__

=head1 NAME

Data::Dumper::Undump - Perl extension for securely and quickly deserializing simple Data::Dumper dumps

=head1 SYNOPSIS

  use Data::Dumper::Undump qw(undump);
  
  my $dump= Data::Dumper->new([$simple_thing])->Terse(1)->Dump();
  undump($dump);

=head1 DESCRIPTION

Securely and quickly deserialize simple Data::Dumper dumps.

=head2 EXPORT

By default exports the undump subroutine.

=head1 SEE ALSO

L<Data::Dumper> L<eval>

=head1 AUTHOR

Yves Orton, E<lt>demerphq@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Yves Orton

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

package Data::Hub::Address;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Programatic;
use Parse::StringTokenizer;

our $Addr_Tokenizer = Parse::StringTokenizer->new(
  -contained  => q({}),
  -quotes     => q('"),
  -delim      => q(/),
);

sub new {
  my $class = ref($_[0]) ? ref(CORE::shift) : CORE::shift;
  my $addr = CORE::shift;
  my @fields = defined $addr ? $Addr_Tokenizer->unpack($addr) : ();
  bless \@fields, $class;
}

sub to_string { my $self = CORE::shift; $Addr_Tokenizer->pack(@$self, @_); }
sub parent    { my @copy = @{$_[0]}; pop @copy; $Addr_Tokenizer->pack(@copy); }
sub first     { $_[0]->[0]; }
sub last      { my $a = $_[0]; $a->[$#$a]; }
sub unshift   { my $a = CORE::shift; CORE::unshift @$a, @_ }
sub shift     { CORE::shift @{$_[0]} }
sub push      { my $a = CORE::shift; CORE::push @$a, @_ }
sub pop       { CORE::pop @{$_[0]} }

1;

=test(!abort)
    
  use strict;
  use Data::Hub::Address;

  my $a = Data::Hub::Address->new("/b/c/d");
  die $a->to_string unless '/b/c/d' eq $a->to_string;
  die $a->first unless '' eq $a->first;
  die $a->last unless 'd' eq $a->last;

  $a->pop;
  die unless '/b/c' eq $a->to_string;

  $a->push("D");
  die unless '/b/c/D' eq $a->to_string;

  $a->shift;
  die unless 'b/c/D' eq $a->to_string;

  $a->unshift('A');
  die unless 'A/b/c/D' eq $a->to_string;

=cut

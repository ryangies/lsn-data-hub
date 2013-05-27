package Data::OrderedHash;
use strict;
use Tie::Hash;
use Perl::Module;
use base qw(Tie::ExtraHash);
our $VERSION = '#{/rundata/ver/lib}#';

sub DATA()    {0} # Underlying hash
sub ORDER()   {1} # Map of key to its position
sub KEY()     {2} # Current key while iterating
sub SORTVAL() {3} # Numeric sort value
sub SEQ()     {4} # Ordered list of keys while iterating

# Class methods

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  tie %$self, $class;
  while (@_) {
    my ($k, $v) = (shift, shift);
    $self->{$k} = $v;
  }
  $self;
}

sub rename_entry {
  my $self = shift;
  tied(%$self)->__rename_entry(@_);
}

sub prepend {
  my $self = shift;
  tied(%$self)->__prepend(@_);
}

sub sort_by_key {
  my $self = shift;
  my $sub = shift;
  die 'Provide a code reference' unless UNIVERSAL::isa($sub, 'CODE');
  my $data = tied(%$self)->[DATA];
  my @key_order = sort {&$sub($a, $b)} keys %$data;
  my $idx = 1; # (start at 1 so ||= logic works)
  my $order = tied(%$self)->[ORDER];
  $order->{$_} = $idx++ for @key_order;
  tied(%$self)->[SORTVAL] = $idx;
}

# Tie methods

sub __rename_entry {
  $_[0][DATA]{$_[2]} = delete $_[0][DATA]{$_[1]};
  $_[0][ORDER]{$_[2]} = delete $_[0][ORDER]{$_[1]};
}

sub __prepend {
  $_[0][DATA]{$_[1]} = $_[2];
  $_[0][ORDER]{$_[1]} = -$_[0][SORTVAL];
  $_[0][SORTVAL]++;
}

sub TIEHASH {
  bless [
    {},     # DATA
    {},     # ORDER
    undef,  # KEY
    1,      # SORTVAL (start at 1 so ||= logic works)
    undef   # SEQ
  ], $_[0];
}

sub STORE {
  $_[0][DATA]{$_[1]} = $_[2];
  $_[0][ORDER]{$_[1]} ||= $_[0][SORTVAL];
  $_[0][SORTVAL]++;
}

sub CLEAR {
  %{$_[0][DATA]} = ();
  %{$_[0][ORDER]} = ();
  $_[0][SORTVAL] = 1;
  $_[0][KEY] = 0;
  undef $_[0][SEQ];
}

sub FIRSTKEY {
  $_[0][KEY] = 0;
  $_[0][SEQ] = [sort {$_[0][ORDER]{$a} <=> $_[0][ORDER]{$b}}
    keys %{$_[0][ORDER]}];
  $_[0][SEQ][0];
}

sub NEXTKEY {
  $_[0][KEY]++;
  $_[0][SEQ][$_[0][KEY]];
}

sub DELETE {
  delete $_[0][ORDER]{$_[1]};
  delete $_[0][DATA]{$_[1]}; # Return
}

1;

__END__

=pod:summary Ordered Hash - First in, first out (FIFO)

=pod:synopsis

=test(match,Apple;Cherry;Banana)

  my %h = ();
  tie %h, 'Data::OrderedHash';
  $h{'first'} = "Apple";
  $h{'second'} = "Cherry";
  $h{'third'} = "Banana";
  join ';', values %h;

=test(match,aXbBcC) # Items retain their initial position

  my $h = Data::OrderedHash->new();
  %$h = qw(a A b B c C);
  $$h{'a'} = 'X';
  join '', %$h;

=test(match,zxyw)

  my $h = Data::OrderedHash->new();
  $h->{'z'} = "Apple";
  $h->{'x'} = "Banana";
  $h->{'y'} = "Cherry";
  my $r = '';
  while (my ($k, $v) = each %$h) { $r .= $k; delete $$h{$k} }
  $h->{'w'} = "Can't elope";
  $r .= join('', keys %$h);
  $r;

=pod:description

The functions C<keys>, C<values>, and C<each> will return the hash entries
in the order they were created.

This package simply maintains a list of the hash keys.  The list is updated
when new items are created (C<STORE>) or deleted (C<DELETE>).  The list is used
when the hash is iterated (C<FIRSTKEY> and C<NEXTKEY>).

=cut

package Data::Hub::Container;
use strict;
use Perl::Module;
use base qw(Exporter Data::Hub::Courier);
our $VERSION = 0;

our @EXPORT_OK = qw(curry);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

sub new {
  return Bless($_[1]) if blessed $_[1];
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $target = ref($_[0]) ? shift : undef;
  my $self = bless $target || {}, $class;
  if (isa($self, 'HASH')) {
    while (@_) {
      my ($k, $v) = (shift, shift);
      $self->{$k} = $v;
    }
  } elsif (isa($self, 'ARRAY')) {
    push @$self, $_ for @_;
  }
  $self;
}

sub Bless {
  my $pkg = ref($_[0]) or return $_[0];
  return $_[0] if isa($_[0], __PACKAGE__);
  if (blessed($_[0])) {
    no strict 'refs';
    push @{"$pkg\::ISA"}, __PACKAGE__;
    return $_[0];
  }
  __PACKAGE__->new($_[0]);
}

sub curry {goto \&Bless}
sub represent {goto \&Bless}
sub get { Bless(Data::Hub::Courier::get(@_)); }
sub list { Bless(Data::Hub::Courier::list(@_)); }

1;

__END__

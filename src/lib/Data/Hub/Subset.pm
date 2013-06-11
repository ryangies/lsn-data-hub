package Data::Hub::Subset;
use strict;
use Perl::Module;
use Data::OrderedHash;
use Data::Hub::Util qw(:all);
use Data::Hub::Container;
use Data::Hub::Courier;
use Data::Hub::Query;
use Data::Hub::ExpandedSubset;
push our @ISA, qw(Data::Hub::Container);

our $VERSION = 0.1;

sub new {
  my $items = Data::OrderedHash->new();
  isa($_[1], __PACKAGE__) and return $_[1];
  # We must create a new container since we will be adding/removing elements
  Data::Hub::Courier::iterate($_[1], sub{$items->{$_[0]} = $_[1]}) if ref($_[1]);
  bless $items, (ref($_[0]) || $_[0]);
}

sub _get {
  my ($self, $index) = @_;
  return unless defined $index;
  my $result = $self->new();
  $self->iterate(sub{
    my $value = Data::Hub::Courier::_get_value($_[1], $index);
    $result->_set_value("$_[0]/$index", $value) if defined($value);
  });
  $result;
}

# Only subsets should do this
sub _expand {
  my $self = shift;
  my $result = Data::Hub::ExpandedSubset->new();
  $self->iterate(sub {
    my $pkey = $_[0];
    if (ref($_[1])) {
      Data::Hub::Courier::iterate($_[1], sub {
        $result->_set_value("$pkey/$_[0]", $_[1]);
      });
    } else {
      $result->_set_value(@_);
    }
  });
  return $result;
}

1;

__END__

=pod

  sub _get {
    my ($self, $index) = @_;
    return $self unless defined $index;
    my $result = undef;
    if ($index =~ RE_ABSTRACT_KEY()) {
      Data::Hub::Query::query($_[0], $_[1])
      
    }
    my $c = substr($index, 0, 1);
    if ($index eq '*') {
      return $self->_expand;
    } elsif ($index =~ /^\{(.*)\}$/) {
      my ($crit, @filters) = split /\|/, $1;
      $result = Data::Hub::Query::_query($self->_expand, $crit);
      for (@filters) {
        s/^\{|\}$//g;
        $result = Data::Hub::Query::_query($result, $_);
      }
    } else {
      $result = $self->new();
      my ($k, @filters) = split /\|/, $index;
      $self->iterate(sub{
        my $value = Data::Hub::Courier::_get_value($_[1], $k);
        $result->_set_value("$_[0]/$k", $value) if defined($value);
      });
      for (@filters) {
        s/^\{|\}$//g;
        $result = Data::Hub::Query::_query($result, $_);
      }
    }
    $result;
  }

=cut

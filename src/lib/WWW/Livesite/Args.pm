package WWW::Livesite::Args;
use strict;
use Perl::Module;
use Data::OrderedHash;
use Tie::Hash;
use base qw(Tie::ExtraHash);
our $VERSION = 0;

our $Field_Delimiter = '&';       # Used when re-creating the query-string
our $Assignment_Operator = '=';   # Used when re-creating the query-string

# ---

sub _unescape {
  my $url = shift;
  $url =~ tr/+/ /;
  $url =~ s/%([a-fA-F0-9]{2})/pack("C",hex($1))/eg;
  $url;
}

sub _escape {
  my $str = shift;
  $str =~ tr/ /+/;
  $str =~ s/([^\w\+])/sprintf('%%%02x',ord($1))/eg;
  $str;
}

sub _to_param {
  my $k = shift;
  my $v = shift;
  if (isa($v, 'ARRAY')) {
    return join $Field_Delimiter, map { $k . $Assignment_Operator . _escape($_) } @$v;
  } else {
    return $k . $Assignment_Operator . _escape($v);
  }
}

# ---

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  tie %$self, $class;
  return $self->parse(@_);
}

sub parse {
  my $self = shift;
  %$self = map {_unescape($_);} split /[=&;]/ for @_;
  return $self;
}

sub as_string {goto \&to_string}
sub to_string {
  my $self = shift;
  join $Field_Delimiter, map { _to_param($_, $$self{$_}) } keys %$self;
}

# ---

sub TIEHASH  {
  my $pkg = shift;
  return bless [Data::OrderedHash->new(), @_], $pkg;
}

sub FETCH {
  my $k = $_[1];
  my $r = $_[0][0]{$k} or return;
  return @$r == 1 ? $r->[0] : $r;
}

sub STORE {
  my $k = $_[1];
  $_[0][0]{$k} ||= [];
  return push @{$_[0][0]{$k}}, $_[2];
}

1;

__END__

=pod:summary Case insensitive query string arguemnts

=pod:synopsis

=test(match,hello world)

  use WWW::Livesite::Args;
  my $qs = WWW::Livesite::Args->new('msg=hello%20world');
  die if defined $qs->{MSG};
  return $qs->{msg};

=test(match,1|2)

  use WWW::Livesite::Args;
  my $qs = WWW::Livesite::Args->new('a=1&a=2');
  my $a = $qs->{a};
  return join '|', @$a;

=pod:description

=cut

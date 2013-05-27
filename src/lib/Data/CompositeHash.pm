package Data::CompositeHash;
use strict;
our $VERSION = 0.1;

use Perl::Module;
use Error::Simple;
use Error::Programatic;
use Data::Hub::Container;
use Data::Hub::Util qw(:all);

# ------------------------------------------------------------------------------
# new - Create a new CompositeHash
# new \%default
# ------------------------------------------------------------------------------
#|test(!abort) use Data::CompositeHash;
#|test(abort) my $ch = Data::CompositeHash->new(); # no default hash provided
# ------------------------------------------------------------------------------

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  my $default = shift or throw Error::MissingArg;
  tie %$self, $class, $default;
  $self;
}

# ------------------------------------------------------------------------------
# shift - Shift a hash from the composite stack
# shift
# ------------------------------------------------------------------------------
#|test(!defined)
#|my $h2 = {a=>'a2'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->shift;
#|$ch->{a};
# ------------------------------------------------------------------------------

sub shift {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self) or throw Error::Programatic;
  CORE::shift @{$tied->__hashes};
}

# ------------------------------------------------------------------------------
# unshift - Unshift hash(es) on to the composite stack
# unshift @hashes
# ------------------------------------------------------------------------------
#|test(match,a1)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->{a};
# ------------------------------------------------------------------------------

sub unshift {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self) or throw Error::Programatic;
  CORE::unshift @{$tied->__hashes}, map {Data::Hub::Container::represent($_)} @_;
}

# ------------------------------------------------------------------------------
# push - Push hash(es) on to the composite stack
# push @hashes
# ------------------------------------------------------------------------------
#|test(match,a2)
#|my $h2 = {a=>'a2'};
#|my $h3 = {a=>'a3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->push($h3);
#|$ch->{a};
# ------------------------------------------------------------------------------

sub push {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self) or throw Error::Programatic;
  CORE::push @{$tied->__hashes}, map {Data::Hub::Container::represent($_)} @_;
}

# ------------------------------------------------------------------------------
# pop - Pop a hash off the composite stack
# pop
# ------------------------------------------------------------------------------
#|test(!defined)
#|my $h2 = {a=>'a2'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->pop;
#|$ch->{a};
# ------------------------------------------------------------------------------

sub pop {
  my $self = CORE::shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self) or throw Error::Programatic;
  CORE::pop @{$tied->__hashes};
}

# ------------------------------------------------------------------------------
# Tie interface
# ------------------------------------------------------------------------------

sub __hashes    { exists $_[1] ? $_[0][0] = $_[1] : $_[0][0] }
sub __default   { exists $_[1] ? $_[0][1] = $_[1] : $_[0][1] }
sub __composite { exists $_[1] ? $_[0][2] = $_[1] : $_[0][2] }

sub TIEHASH  {
  my $class = CORE::shift;
  my $default = Data::Hub::Container::represent(CORE::shift);
  throw Error::IllegalArg "provide a hash" unless isa($default, 'HASH');
  bless [
    [$default], # __hashes
    $default, # __default
    {}, # __composite
  ], $class;
}

# ------------------------------------------------------------------------------
#|test(!abort)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $h3 = {a=>'a3', b=>'b3', c=>'c3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->push($h3);
#|# We now have a composite stack with prescedence: $h1, $h2, $h3
#|# Where $h2 is the default hash
#|$ch->{a} = 'AA';
#|$ch->{b} = 'BB';
#|$ch->{c} = 'CC';
#|$ch->{d} = 'DD';
#|die unless $h1->{a} eq 'AA';
#|die unless $h2->{b} eq 'BB';
#|die unless $h3->{c} eq 'CC';
#|die unless $h2->{d} eq 'DD'; # set on default hash b/c 'd' did not exist
# ------------------------------------------------------------------------------

sub STORE {
  my @keys = addr_split($_[1]) or return;
  my $root_key  = CORE::shift @keys;
  my $idx = 0;
  my $hash = undef;
  for (@{$_[0]->__hashes}) {
    $hash = $_ if exists $_->{$root_key};
    last if defined $hash;
  }
  if (defined $hash) {
    return $hash->set($_[1], $_[2]);
  } else {
    return $_[0]->__default->set($_[1], $_[2]);
  }
}

# ------------------------------------------------------------------------------
#|test(!abort)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $h3 = {a=>'a3', b=>'b3', c=>'c3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->push($h3);
#|# We now have a composite stack with prescedence: $h1, $h2, $h3
#|# Where $h2 is the default hash
#|die unless $ch->{a} eq 'a1';
#|die unless $ch->{b} eq 'b2';
#|die unless $ch->{c} eq 'c3';
#|die unless ref($ch->{'/'});
# ------------------------------------------------------------------------------

sub FETCH {
  my $key = $_[1]; # copy b/c addr_shift updates the string
  $key eq '/' and return $_[0]->__default;
  my $c = undef;
  my $fk = addr_shift($key);
  if (is_abstract_key($fk)) {
    $c = $_[0]->__default->get($fk); # query
  } else {
    for (@{$_[0]->__hashes}) {
      # The first-key may be present in multiple hashes, we select the first
      my $k = grep_first {$_ eq $fk} keys %$_;
      next unless defined $k;
      $c = curry($_->{$k});
      last;
    }
  }
  return defined $c && length($key) ? $c->get($key) : $c;
}

# ------------------------------------------------------------------------------
#|test(match,a1b2c3)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $h3 = {a=>'a3', b=>'b3', c=>'c3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->push($h3);
#|join '', sort values %$ch;
# ------------------------------------------------------------------------------

sub FIRSTKEY {
  $_[0]->__composite({map {%$_} @{$_[0]->__hashes}});
  my $reset = scalar keys %{$_[0]->__composite};
  each %{$_[0]->__composite}
}

sub NEXTKEY {
  each %{$_[0]->__composite}
}

# ------------------------------------------------------------------------------
#|test(!abort)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $h3 = {a=>'a3', b=>'b3', c=>'c3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->push($h3);
#|die unless exists $$ch{a};
#|die unless exists $$ch{b};
#|die unless exists $$ch{c};
#|die if exists $$ch{d};
# ------------------------------------------------------------------------------

sub EXISTS {
  for (@{$_[0]->__hashes}) {
    return 1 if $_->get($_[1]);
  }
  undef;
}

# ------------------------------------------------------------------------------
#|test(match,a2b3)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $h3 = {a=>'a3', b=>'b3', c=>'c3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->push($h3);
#|delete $ch->{a};
#|delete $ch->{b};
#|delete $ch->{c};
#|join '', sort values %$ch;
# ------------------------------------------------------------------------------

sub DELETE {
  for (@{$_[0]->__hashes}) {
    return if $_->delete($_[1]);
  }
  undef;
}

# ------------------------------------------------------------------------------
#|test(match,a2b2)
#|my $h1 = {a=>'a1'};
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $h3 = {a=>'a3', b=>'b3', c=>'c3'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->unshift($h1);
#|$ch->push($h3);
#|%$ch = ();
#|join '', sort values %$ch;
# ------------------------------------------------------------------------------

sub CLEAR {
  # does NOT clear default hash
  $_[0]->__hashes([$_[0]->__default]),
  $_[0]->__composite({}),
}

# ------------------------------------------------------------------------------
#|test(true)
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $ch = Data::CompositeHash->new($h2);
#|scalar(%$ch);
# ------------------------------------------------------------------------------
#|test(false)
#|my $h2 = {a=>'a2', b=>'b2'};
#|my $ch = Data::CompositeHash->new($h2);
#|$ch->pop;
#|scalar(%$ch);
# ------------------------------------------------------------------------------

sub SCALAR {
  join ':', map {scalar %$_} @{$_[0]->__hashes};
}

=test(match)

  use Data::CompositeHash;

  my $h1 = {
    'a' => 'argon',
  };

  my $h2 = {
    'a' => 'apple',
    'b' => 'banana',
    'c' => 'cherry',
  };

  my $h3 = {
    'c' => 'cyan',
    'd' => 'dark brown',
  };

  my $result = '';

  # Create a composite hash, using $h2 as the default hash
  my $ch = Data::CompositeHash->new($h2);

  # Add $h1 as a hash which will overried values in $h2
  $ch->unshift($h1);

  # Add $h3 as a hash with the least prescedence
  $ch->push($h3);

  # Fetch some values
  $result .= $ch->{a} . "\n";
  $result .= $ch->{b} . "\n";
  $result .= $ch->{c} . "\n";
  $result .= $ch->{d} . "\n";

  # Set an ambiguous value
  $result .= "--\n";
  $ch->{a} = 'aluminium';
  $result .= $h1->{a} . "\n"; # contains new value
  $result .= $h2->{a} . "\n"; # not touched

  # Set an ambiguous value
  $result .= "--\n";
  $ch->{c} = 'cantelope';
  $result .= $h2->{c} . "\n"; # contains new value
  $result .= $h3->{c} . "\n"; # not touched

  # Setting a value which is not defined in any hash sets
  # it on the defalut hash
  $result .= "--\n";
  $ch->{e} = 'edible fruit';
  $result .= $h2->{e};


=result

  argon
  banana
  cherry
  dark brown
  --
  aluminium
  apple
  --
  cantelope
  cyan
  --
  edible fruit

=cut

1;

package WWW::Livesite::Headers;
use strict;
our $VERSION = 0.1;

# ------------------------------------------------------------------------------
# TODO - Wrap (subclass) HTTP::Headers
# ------------------------------------------------------------------------------

use Perl::Module;
use Data::OrderedHash;
use Tie::Hash;
use base qw(Tie::ExtraHash);

# The assignment operator
our $Assign = ':';

# The field delimiter
our $Delim = "\n";

# Singletons are items which will not fork into an array.
# (ensure these names are normalized)
our @Singletons = qw(
  Content-Type
  Content-Disposition
  Cache-Control
  Expires
  Date
  ETag
  Last-Modified
);

# ---

sub _unescape {
  my $str = shift;
  $str;
}

sub _escape {
  my $str = shift;
  $str;
}

sub _to_param {
  my $k = shift;
  my $v = shift;
  if (isa($v, 'ARRAY')) {
    return join $Delim, map { $k . $Assign . ' ' . _escape($_) } @$v;
  } else {
    return $k . $Assign . ' ' . _escape($v);
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
  for (@_) {
    for (split $Delim) {
      my ($k, $v) = $_ =~ /^([^$Assign]+)$Assign\s*(.*)/s;
      $self->{$k} = $v;
    }
  }
  return $self;
}

sub as_array {
  my $self = shift;
  my @fields = ();
  for (keys %$self) {
    next if $_ eq 'Content-Type';
    my $v = $$self{$_};
    if (isa($v, 'ARRAY')) {
      foreach my $vv (@$v) {
        push @fields, [$_, _escape($vv)];
      }
    } else {
      push @fields, [$_, _escape($v)];
    }

  }
  if (my $ct = $$self{'Content-Type'}) {
    push @fields, ['Content-Type', _escape($ct)];
  }
  @fields;
}

sub to_string {
  my $self = shift;
  my @fields = ();
  my $ct = undef; # Content-Type
  for (keys %$self) {
    my $field = _to_param($_, $$self{$_});
    if ($_ eq 'Content-Type') {
      $ct = $field;
    } else {
      push @fields, $field;
    }
  }
  if ($ct) {
    # Always comes last, and has an extra newline
    push @fields, $ct, '';
  }
  join $Delim, @fields;
}

# ---

sub TIEHASH  {
  my $pkg = shift;
  return bless [Data::OrderedHash->new(), @_], $pkg;
}

sub _normalize_key {
  $_[0] =~ s/\b([a-z])/uc($1)/eg;
  $_[0];
}

sub FETCH {
  my $k = _normalize_key($_[1]);
  my $r = $_[0][0]{$k} or return;
  return @$r == 1 ? $r->[0] : $r;
}

sub STORE {
  my $k = _normalize_key($_[1]);
  # Setting to a reference overrides our internal behavior
  return $_[0][0]{$k} = $_[2] if ref($_[2]);
  $_[0][0]{$k} ||= [];
  if (grep_first(sub {$k eq $_}, @Singletons)) {
    # Singletons do not append to the array.
    return $_[0][0]{$k}[0] = $_[2];
  }
  return push @{$_[0][0]{$k}}, $_[2];
}

1;

__END__

=pod:summary HTTP Header Hash

=pod:synopsis

  use WWW::Livesite::Headers;
  my $h = WWW::Livesite::Headers->new();
  $h->parse($header_str);
  $$h{'Pragma'} = 'no-cache';
  print $h->to_string, "\n";
  for ($h->as_array) {
    printf "%s: %s\n", @$_;
  }

=pod:description

  #!/usr/bin/perl
  use strict;
  use warnings FATAL => qw(all);
  use WWW::Livesite::Headers;

  my $str = <<__end;
  Pragma: no-cache
  Server: lws
  Date: now
  Content-Type: text/plain
  __end

  # Create a new headers object
  my $h = WWW::Livesite::Headers->new();

  # Parse the above headers (this could also have been done by
  # passing $str to the constructor).
  $h->parse($str);

  # Set a new header
  $$h{'Cache-control'} = 'no-cache, no-store, max-age=0';

  # Set the special content-type header (will always output last)
  $$h{'content-Type'} = 'text/html';

  # Setting a value for one which exists forks it into an array,
  # meaning there are two header fields.
  $$h{'Pragma'} = 'repeat';

  # Set a value unless it already exists
  $$h{'Server'} ||= 'MyServer';

  # Override a value (avoid the forking behavior by assigning an
  # array).  If the array were to have two items, it would result
  # in two header fields.
  $$h{'Date'} = ['12/30/73'];

  # Set another header (and notice that it is upper-cased on output).
  $$h{'expires'} = '0';

  # Output the string.  Notice that the fields are printed in FIFO order as
  # to when their key was added to the hash, with the exception of 
  # 'Content-Type', which is always last (and gets an extra newline).
  print $h->to_string, "\n";

  # The as_array method provides an entry for each header.  The entry is
  # an array reference with to items, the name and its definition.
  for ($h->as_array) {
    my ($k, $v) = @$_;
    print "<$k>$v</$k>\n";
  }

Sample output of the above

  Pragma: no-cache
  Pragma: repeat
  Server: lws
  Date: 12/30/73
  Cache-Control: no-cache, no-store, max-age=0
  Expires: 0
  Content-Type: text/html

  <Pragma>no-cache</Pragma>
  <Pragma>repeat</Pragma>
  <Server>lws</Server>
  <Date>12/30/73</Date>
  <Cache-Control>no-cache, no-store, max-age=0</Cache-Control>
  <Expires>0</Expires>
  <Content-Type>text/html</Content-Type>


=cut

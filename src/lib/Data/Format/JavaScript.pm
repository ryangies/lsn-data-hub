package Data::Format::JavaScript;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Programatic;
use Scalar::Util qw(looks_like_number);
use base qw(Exporter);

our @EXPORT_OK = qw(
  js_format
  js_format_key
  js_format_value
  js_format_string
  js_format_lsn
);

our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

sub get_instance {
  __PACKAGE__->new(@_);
}

sub js_format {
  my $opts = my_opts(\@_);
  get_instance(-opts => $opts)->format(@_);
}

sub js_format_key {
  get_instance()->format_key(@_);
}

sub js_format_value {
  get_instance()->format_value(@_);
}

sub js_format_string {
  get_instance()->format_string(@_);
}

sub js_format_lsn {
  get_instance()->format_lsn(@_);
}

# ------------------------------------------------------------------------------

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $opts = my_opts(\@_, {
      include_hidden => 0,
      indent => 0,
    });
  my $self = bless {
    opts => $opts,
    tab => '  ',
    depth => 0,
  }, $classname;
  $self;
}

sub append {
  my $self = shift;
  my $content = shift;
  my $indent = $$self{'opts'}{'indent'} ? $$self{'tab'} x $$self{'depth'} : '';
  my $newline = $$self{'opts'}{'indent'} ? "\n" : '';
  my $str = sprintf("%s%s%s", $indent, $content, $newline);
  $str;
}

sub is_empty {
  my $self = shift;
  my $unk = shift;
  return !defined($unk)
    || $unk eq ''
    || $unk eq 'null'
    || (isa($unk, 'ARRAY') && !@$unk)
    || (isa($unk, 'HASH') && !%$unk)
    ;
}

sub format {
  my $self = shift;
  my ($item) = @_;
  my $result = q();
  if (!defined $item) {
    $result = q("");
  } elsif (isa($item, 'HASH')) {
    $result = $self->append('{');
    $$self{'depth'}++;
    my @keys = $$self{'opts'}{'include_hidden'} ? keys %$item : grep {!/^\./} keys %$item;
    my @out = ();
    while (@keys) {
      my $k = shift @keys;
      next if $$self{'opts'}{'omit_empty'} && $self->is_empty($$item{$k});
      push @out, sprintf "%s:%s", $self->format_key($k), $self->format($$item{$k});
    }
    while (@out) {
      my $out = shift @out;
      $out .= "," if @out;
      $result .= $self->append($out);
    }
    $$self{'depth'}--;
    $result .= $self->append('}');
  } elsif (isa($item, 'ARRAY')) {
    $result = $self->append('[');
    $$self{'depth'}++;
    my $num_items = @$item;
    my $num = 1;
    foreach my $v (@$item) {
      my $out = $self->format($v);
      $out .= "," unless $num++ == $num_items;
      $result .= $self->append($out);
    }
    $$self{'depth'}--;
    $result .= $self->append(']');
  } else {
    $result = $self->format_value($item);
  }
  $result;
}

sub format_lsn {
  my $self = shift;
  my ($item) = @_;
  if (!defined $item) {
    return q("");
  } elsif (isa($item, 'HASH')) {
    return 'new LSN.OrderedHash(' . join(",", map {$self->format_key($_) . ', ' . $self->format_lsn($$item{$_})}
      grep {!/^\./} keys %$item) . ")";
  } elsif (isa($item, 'ARRAY')) {
    return 'new LSN.Array(' . join(",", map {$self->format_lsn($_)} @$item) . ')';
  } else {
    return $self->format_value($item);
  }
}

sub format_key {
  my $self = shift;
  my $key = shift;
  $key =~ s/(?<!\\)(["])/\\$1/g;
  $key =~ s/\//&#x2f;/g;
  return '"' . $key . '"';
}

sub format_value {
  my $self = shift;
  my $value = shift;
  isa($value, 'JSON::PP::Boolean') and return $value ? 'true' : 'false';
  isa($value, 'SCALAR') and $value = $$value;
  return $value if looks_like_number($value);
  return $value if $value =~ /^(null|NaN|undefined|true|false|\s*function\s*\()$/;
  return $self->format_string($value);
}

sub format_string {
  my $self = shift;
  my $value = shift;
  isa($value, 'SCALAR') and $value = $$value;
  $value =~ s/^'(null|NaN|undefined|true|false|[0-9]|[1-9][\d\.]+)$/$1/;
  $value =~ s/([\\"])/\\$1/gm;
  $value =~ s/(\r?\n\r?|\r)/\\n/gm;
  return '"' . $value . '"';
}

1;

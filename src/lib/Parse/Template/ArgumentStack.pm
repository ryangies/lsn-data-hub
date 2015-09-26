package Parse::Template::ArgumentStack;
use strict;
use Perl::Module;
use Perl::Compare qw(compare);
use Error::Programatic;
use Error::Logical;
use Data::Hub::Util qw(FS %TYPEOF_ALIASES typeof curry);

our %BINARY_OPERATORS = ();
our %UNARY_OPERATORS = ();

# Binary operators

foreach my $opr (keys %Perl::Compare::COMPARISONS) {
  $BINARY_OPERATORS{$opr} = sub {
    my ($self, $y, $x) = @_;
    my $y_val = $self->get_compiled_value($y);
    my $x_val = $self->get_compiled_value($x);
#warn "stack-compare: $opr, $y_val, $x_val\n";
    return compare($opr, $y_val, $x_val);
  };
}

$BINARY_OPERATORS{'&&'} = sub {
  my ($self, $y, $x) = @_;
  my $b = $self->get_boolean_value($y);
  $b and $b = $self->get_boolean_value($x);
  $b;
};

$BINARY_OPERATORS{'||'} = sub {
  my ($self, $y, $x) = @_;
  my $b = $self->get_boolean_value($y);
  !$b and $b = $self->get_boolean_value($x);
  $b;
};

# Unary operators

$UNARY_OPERATORS{'!'} = sub {
  my ($self, $x) = @_;
  return !$self->get_boolean_value($x);
};

$UNARY_OPERATORS{'-data'} = sub {
  my ($self, $x) = @_;
  my $v = $self->get_value($x);
  if (defined($v)) {
    if (ref($v) && can($v, 'length')) {
      $v = $v->length;
    } else {
      $v = 0;
    }
  }
  return $v > 0 ? 1 : 0;
};

$UNARY_OPERATORS{'-defined'} = sub {
  my ($self, $x) = @_;
  my $v = $self->get_value($x);
  return defined $v;
};

$UNARY_OPERATORS{'-content'} = sub {
  my ($self, $x) = @_;
  my $v = $self->get_value($x);
  $v = defined($v)
    ? ref($v)
      ? isa($v, FS('TextFile'))
        ? length($v->get_content)
        : 0
      : length($v)
    : 0;
  return $v > 0 ? 1 : 0;
};

$UNARY_OPERATORS{'-ref'} = sub {
  my ($self, $x) = @_;
  return ref($self->get_value($x)) ? 1 : 0;
};

foreach my $alias (keys %TYPEOF_ALIASES) {
  my $type = $TYPEOF_ALIASES{$alias};
  my $opr = $type =~ s/^([=!]~)// ? $1 : 'eq';
  $UNARY_OPERATORS{"-$alias"} = sub {
    my ($self, $x) = @_;
    return compare($opr, typeof('', $self->get_value($x)), $type);
  }
}

# new($parser, $args);

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my ($parser, $args) = (shift, shift);
  throw Error::IllegalArg 'Bad parser' unless isa($parser, 'Parse::Template::Base');
  throw Error::IllegalArg 'Bad argument list' unless isa($args, 'ARRAY');
  my $self = bless [], $classname;
  $self->[0] = $parser;
  $self->[1] = $self->parse($args, @_);
  return $self;
}

sub parse {
  my $self = shift;
  my $args = shift;
  my $beg = shift || 0;
  my $tmp = [];
  my $stack = [];
  for (my $i = $beg; $i < @$args; $i++) {
    push @$tmp, isa($args->[$i], 'Parse::Template::CallbackArgument')
      ? $args->[$i]
      : ref($args->[$i])
        ? $self->parse($args->[$i])
        : $args->[$i];
  }
  while (@$tmp) {
    my $arg = $self->next_arg($tmp);
    if (!ref($arg) && $BINARY_OPERATORS{$arg}) {
      push @$stack, $self->next_arg($tmp);
    }
    push @$stack, $arg;
  }
  return $stack;
}

sub next_arg {
  my $self = shift;
  my $args = shift;
  my $arg = shift @$args;
  return $arg if ref($arg) || !$UNARY_OPERATORS{$arg};
  my $result = [$arg];
  while (@$args) {
    $arg = shift @$args;
    unshift @$result, $arg;
    last if ref($arg) || !$UNARY_OPERATORS{$arg};
  }
  return $result;
}

sub eval {
  return $_[1] if defined($_[1]) && !ref($_[1]);
  my $self = shift;
  my $stack = shift || $self->[1];
  while (@$stack) {
#no warnings;
    my $y = shift @$stack;
    my $x = shift @$stack;
#warn "stack-eval: x=$x y=$y\n";
    if (!defined($x)) {
      return $self->get_boolean_value($y);
    } elsif (my $sub = $UNARY_OPERATORS{$x}) {
#warn "stack-eval: unary\n";
      my $arg = &$sub($self, $y);
      unshift @$stack, $arg;
    } else {
      my $o = shift @$stack;
      if (my $sub = $BINARY_OPERATORS{$o}) {
#warn "stack-eval: operator=$o\n";
        my $arg = &$sub($self, $y, $x);
#warn "stack-eval: binary='$arg'\n";
        unshift @$stack, $arg;
      } else {
        throw Error::Logical "Unknown binary operator: '$o'";
      }
    }
  }
  my $sz = @$stack;
  throw Error::Logical "Bad stack size: $sz" unless $sz == 1;
  pop @$stack;
}

sub get_boolean_value {
  my ($self, $var) = @_;
  return $self->eval($var) if isa($var, 'ARRAY');
  throw Error::Logical if ref($var);
  my $value = $self->[0]->get_value(\$var);
  if (defined($value)) {
    if (isa($value, 'CODE')) {
      $value = $self->[0]->value_eval($value);
    }
    if (ref($value)) {
      $value = isa($value, FS('Node')) ? 1 : curry($value)->length();
    }
  }
  return $value ? 1 : 0;
}

sub get_compiled_value {
  my ($self, $var) = @_;
  return $self->[0]->get_compiled_value(\$var) if isa($var, 'Parse::Template::CallbackArgument');
  return $self->eval($var) if isa($var, 'ARRAY');
  return $self->[0]->get_compiled_value(\$var);
}

sub get_value {
  my ($self, $var) = @_;
  return $self->[0]->get_value(\$var) if isa($var, 'Parse::Template::CallbackArgument');
  return $self->eval($var) if isa($var, 'ARRAY');
  return $self->[0]->get_value(\$var);
}

1;

__END__

=pod

TODO - These will work, however the divide '/' could be mistaken
when the arg really refers to the root node...

TODO - Such math should be supported, however `eval` current takes
the last arg on the stack and turns it into a boolean, rather than
returning the computed value...

$BINARY_OPERATORS{'+'} = sub {
  my ($self, $y, $x) = @_;
  my $y_val = $self->get_compiled_value($y);
  my $x_val = $self->get_compiled_value($x);
  $y_val + $x_val;
};

$BINARY_OPERATORS{'-'} = sub {
  my ($self, $y, $x) = @_;
  my $y_val = $self->get_compiled_value($y);
  my $x_val = $self->get_compiled_value($x);
  $y_val - $x_val;
};

$BINARY_OPERATORS{'*'} = sub {
  my ($self, $y, $x) = @_;
  my $y_val = $self->get_compiled_value($y);
  my $x_val = $self->get_compiled_value($x);
  $y_val * $x_val;
};

$BINARY_OPERATORS{'/'} = sub {
  my ($self, $y, $x) = @_;
  my $y_val = $self->get_compiled_value($y);
  my $x_val = $self->get_compiled_value($x);
  $y_val / $x_val;
};

=cut

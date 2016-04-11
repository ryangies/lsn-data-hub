package Parse::Template::Base;
use strict;
our $VERSION = 0.1;

use Perl::Module;
use Data::Hub::Util qw(:all);
use Data::Hub::Courier;
use Error::Programatic;
use Error::Logical;
use Algorithm::KeyGen qw($KeyGen);
use Parse::Padding qw(:all);
use Parse::Template::Arguments;
use Parse::Template::ArgumentStack;

our %Directives = ();

our $Regex_Var_Name = qr([a-zA-Z_\-][a-zA-Z0-9_\-]*);

# ------------------------------------------------------------------------------
# new - Constructor
# new [options]
#
# options:
#
#   -begin => $begin_str          # Begins match (default '[#')
#   -end => $end_str              # Ends match (default ']')
#   -close => $close_str          # Closes a block (default 'end')
#   -directive => $directive_str  # Identifies a directive (default ':')
#   -out => \$output              # Where output is written
# ------------------------------------------------------------------------------

sub new {
  my $class = shift;
  my ($opts) = my_opts(\@_, {
    begin => '[#',
    end => ']',
    close => 'end',
    close_sep => ' ',
    directive => ':',
  });
  my $self = bless {
    bs => $opts->{begin},
    bc => _extract_ambigous_pattern_char($opts->{begin}),
    es => $opts->{end},
    ec => _extract_ambigous_pattern_char($opts->{end}),
    cs => $opts->{close},
    ds => $opts->{directive},
    bs_len => length($opts->{begin}),
    es_len => length($opts->{end}),
    ds_len => length($opts->{directive}),
    cs_sep => $opts->{close_sep},
    root_stack => [],
    stack => [],
    directives => {},
    directives_cache => {},
    ctx => [],
    out => $opts->{out},
    replace_count => 0,
    dbgout => $opts->{dbgout},
    opts => $opts,
  }, (ref($class) || $class);
  $self;
}

sub _extract_ambigous_pattern_char {
  my $str = shift;
  foreach my $c (split //, $str) {
    return $c if $c =~ tr/[]<>{}//;
  }
  substr($str,0,1);
}

# ------------------------------------------------------------------------------
# Default_Context - Default (initial) context
# ------------------------------------------------------------------------------

sub Default_Context {
  my $self = shift;
  my $text = '';
  my $root = $self->{root_stack}[0];
  my $pwd = $root ? $root->{'./'} : undef;
  return {
    path => $pwd ? $pwd->get_addr : undef,
    name => undef,
    out => $self->{out},
    text => \$text,
    len => 0,
    scope => 0, # limit where to start searching local stack
    pos => 0,
  };
}

# ------------------------------------------------------------------------------
# set_directives - Set the directive handlers for each given name-value pair
# set_directives @directives
# ------------------------------------------------------------------------------

sub set_directives {
  my $self = shift;
  my %directives = @_;
  while (@_) {
    $self->set_directive(shift, shift);
  }
}

# ------------------------------------------------------------------------------
# set_directive - Set the directive handler for a given name-value pair
# set_directive $name, \@subs
# ------------------------------------------------------------------------------

sub set_directive {
  my $self = shift;
  my $name = shift or throw Error::MissingArg;
  my $subs = shift or throw Error::MissingArg;
  #throw Error::IllegalArg unless isa($subs, 'ARRAY');
  $self->{directives}{$name} = $subs;
}

# ------------------------------------------------------------------------------
# get_directive - Get a directive handler
# get_directive $name, $idx
# where:
#   $name   directive name
#   $idx    0 for begin, 1 for end
# ------------------------------------------------------------------------------

sub get_directive {
  my $self = shift;
  my $result = $self->{directives_cache}{$_[0]}[$_[1]];
  return $result if $result;
  my @name = split ':', $_[0];
  if (@name > 1) {
    my $ptr = $self->{directives};
    for (@name) {
      $ptr = $ptr->{$_};
      last unless $ptr && isa($ptr, 'HASH');
    }
    isa($ptr, 'ARRAY') and $result = $ptr->[$_[1]];
  } else {
    my $directive = $self->{directives}{$_[0]} or return;
    isa($directive, 'HASH') and $directive = $directive->{'*'};
    isa($directive, 'ARRAY') and $result = $directive->[$_[1]];
    isa($directive, 'CODE') and $result = $directive; # used for both beg/end
  }
  return $self->{directives_cache}{$_[0]}[$_[1]] = $result;
}

# ------------------------------------------------------------------------------
# compile - Main invokation method
# compile $addr, [options]
# compile $addr, @namespaces, [options]
# ------------------------------------------------------------------------------

sub compile {
  my $self = shift;
  my $addr = shift or throw Error::MissingArg;
  my $node = $self->get_value(\$addr) or warn "Cannot find template: $addr";
  my $text = $self->value_to_string($node);
  return unless defined $text;
  my $path = addr_parent($addr);
  my $name = addr_name($addr);
  $self->compile_text(\$text, -path => $path, -name => $name, @_, $node);
}

# ------------------------------------------------------------------------------
# compile_text - Main invokation method
# compile_text $text, [options]
# compile_text $text, @namespaces, [options]
# ------------------------------------------------------------------------------

sub compile_text(\$\$@) {
  my $self = shift;
  my $text = str_ref(shift);
  throw Error::IllegalArg '$text must be a scalar reference'
    unless isa($text, 'SCALAR');
  my $opts = my_opts(\@_);
  if (!defined($opts->{out}) && !defined($self->{out})) {
    $opts->{out} = str_ref('');
  }
  throw Error::IllegalArg '-out must be a scalar reference'
    if (defined($opts->{out}) && !isa($opts->{out}, 'SCALAR'));
  $self->{replace_count} = 0;
  @_ and $self->use(@_);
  $self->{dbgout} and ${$self->{dbgout}} = 'SIG_BEGIN';
  my $ctx = $self->_invoke(text => $text, %$opts);
  @_ and $self->unuse();
  $self->{dbgout} and ${$self->{dbgout}} = 'SIG_END';
  $ctx->{out};
}

# ------------------------------------------------------------------------------
# get_ctx - Get the current context from the context stack
# get_ctx
# ------------------------------------------------------------------------------

sub get_ctx(\$) {
  $_[0]->{ctx}[0] || $_[0]->Default_Context;
}

# ------------------------------------------------------------------------------
# use - Add a namespace on to the local stack
# Calls to use must match calls to un-use within the same context
# ------------------------------------------------------------------------------

sub use {
  my $self = shift;
  my @items = ();
  while (@_) {
    my $tk = shift or next;
    my $ns = [];
    if (ref($tk)) {
      $ns->[0] = curry($tk);
      $ns->[1] = can($tk, 'get_addr') ? $tk->get_addr : undef;
    } else {
      $ns->[0] = curry(shift);
      $ns->[1] = $tk;
    }
    next unless isa($ns->[0], 'HASH');
    next if $ns->[0]->length() < 1;
    push @items, $ns;
  }
  my $sz = @items;
  unshift @{$$self{stack}}, @items;
  push @{$$self{'used_sz'}}, $sz;
}

# ------------------------------------------------------------------------------
# unuse - Remove the last used namespace from the local stack
# Calls to use must match calls to un-use within the same context
# ------------------------------------------------------------------------------

sub unuse {
  my $self = shift;
  my $sz = pop @{$$self{'used_sz'}};
  return unless defined $sz;
  splice @{$$self{stack}}, 0, $sz;
}

# ------------------------------------------------------------------------------
# _create_context - Add a new context on to the context stack
# _create_context %args
# where C<%args> can be any combination of:
#   text      => \$text,    # Template text
#   path      => $path,     # Template path
#   name      => $name,     # Template name
#   out       => \$out,     # Where to write the result
#   scope     => $scope,    # Stack index limit (invokation is being deferred)
#   regions   => \@regions, # Known regions (\$text is being re-used)
#   esc       => $chars     # Escape chars in resolved values
# ------------------------------------------------------------------------------

sub _create_context {
  my $self = shift;
  my %args = @_;
  my $ctx = {
    pos => 0, # current position
    reg => 0, # current region
  };
  for (qw(text out path name esc)) {
    my $arg = $args{$_};
    $arg = $self->get_ctx->{$_} unless defined $arg;
    $ctx->{$_} = $arg;
  }
  unless (defined $ctx->{text} && isa($ctx->{text}, 'SCALAR') &&
      defined ${$ctx->{text}}) {
    my $msg = 'Missing template resource';
    if (defined $args{'path'} && defined $args{'name'}) {
      $msg .= ": $args{'path'}/$args{'name'}";
      throw Error::Logical $msg;
    }
  }
  $ctx->{vars} = Data::Hub::Container->new();
  if (defined $args{'path'} && defined $args{'name'}) {
    $ctx->{vars}{UID2} = 'UID' . $KeyGen->create();
  }
  $ctx->{scope} = $args{scope} || 0; # do not inherit
  $ctx->{regions} = defined $args{regions}
    ? $args{regions}
    : $self->_find_regions($ctx->{text});
  $ctx->{len} = length(${$ctx->{text}});
  $ctx->{orig_stack_sz} = @{$self->{stack}};
  if (!@{$self->{ctx}}) {
    $ctx->{vars}{UID} = 'UID' . $KeyGen->create();
  }
  unshift @{$self->{ctx}}, $ctx;
  $ctx;
}

# ------------------------------------------------------------------------------
# _find_regions - Glean the begin and end indexes into template text
# _find_regions \$text
# _find_regions \$text, $beg_str, $end_str
# returns:
#   [\@match1, \@match2, ...]
# where each C<\@match> is:
#   [
#     $beg,       # Begin index
#     $end,       # End index
#     $nested,    # Has nested regions (1|undef)
#   ]
# ------------------------------------------------------------------------------

sub _find_regions {
  my $self = shift;
  my $txt = shift;
  my $beg_str = $_[0] || $self->{bs};
  my $end_str = $_[1] || $self->{es};
  my $beg_len = length($beg_str);
  my $end_len = length($end_str);
  my $beg2_str = $_[0] ? $beg_str : $self->{bc};
  my $end2_str = $_[1] ? $end_str : $self->{ec};
  my $beg2_len = length($beg2_str);
  my $end2_len = length($end2_str);

  confess "Bad text pointer" unless ref($txt);

  my $result = [];
  my ($p, $b, $e) = (0, undef, undef);
  while ($p >= 0) {
    my $match = [];
    $b = index $$txt, $beg_str, $p;
    last if $b < 0;
    $match->[0] = $b;
    $e = index $$txt, $end_str, $b;
    my $b2 = index $$txt, $beg2_str, $b + $beg_len;
    while ($b2 > $b && $b2 < $e && $e > $b) {
      $match->[2] = 1;
      $e = index $$txt, $end_str, $e + $end_len;
      $b2 = index $$txt, $beg2_str, $b2 + $beg2_len;
    }
    $e = length($$txt) if $e < 0;
    $match->[1] = $e;
    push @$result, $match;
    $p = $e;
  }
  $result;
}

# ------------------------------------------------------------------------------
# _remove_context - Remove the current context from the context stack
# ------------------------------------------------------------------------------

sub _remove_context {
  my $self = shift;
  my $ctx = shift @{$$self{ctx}};
  # Remove stack items which were not explicitly unused
  my $stack_sz = @{$self->{stack}};
  if ($ctx->{orig_stack_sz} < $stack_sz) {
    my $sz = $stack_sz - $ctx->{orig_stack_sz};
    splice @{$self->{stack}}, 0, $sz;
    my $used_sz = 0;
    # Remove the counts from the unuse memory
    for (reverse @{$self->{used_sz}}) {
      pop @{$self->{used_sz}};
      $used_sz += $_;
      last if $used_sz == $sz;
      # if we removed more items from the stack than expected
      throw Error::Programatic if $used_sz > $sz;
    }
  }
  $ctx;
}

# ------------------------------------------------------------------------------
# _invoke - Implementation method
# _invoke 
# _invoke %args
# See _create_context for C<%args>
# ------------------------------------------------------------------------------

sub _invoke {
  my $self = shift;
  my $ctx = $self->_create_context(@_);
  while (1) {
    $ctx->{elem} = undef;
    # Find the next region
    my $region = undef;
    while ($region = $$ctx{regions}->[$$ctx{reg}++]) {
      last if $$region[0] >= $$ctx{pos};
    }
    unless ($region) {
      # End of population
      if ($$ctx{pos} < $$ctx{len}) {
        ${$$ctx{out}} .= substr ${$$ctx{text}}, $$ctx{pos};
      }
      last;
    }
    my ($b, $e) = ($$region[0], $$region[1]);
    # Begin, End, and Width of current region
    $ctx->{elem}{B} = $b;
    $ctx->{elem}{E} = $e + $self->{es_len};
    $ctx->{elem}{W} = $ctx->{elem}{E} - $ctx->{elem}{B};
    # Extract current element
    $ctx->{elem}{b} = $b + $$self{bs_len};
    $ctx->{elem}{w} = $e - $ctx->{elem}{b};
    $ctx->{elem}{t} = substr ${$$ctx{text}}, $ctx->{elem}{b}, $ctx->{elem}{w};
    $self->{dbgout} and ${$self->{dbgout}} = 'SIG_MATCH';
    # Evaluate inner elements
    if ($$region[2]) {
      my $out = '';
      $ctx->{elem}{t} = $self->_invoke(text => \$ctx->{elem}{t}, out => \$out, esc => '"\'');
      $ctx->{elem}{t} = $out;
#warn 'out: ', $out, "\n";
      $self->{dbgout} and ${$self->{dbgout}} = 'SIG_MATCH';
    }
    # Evaluate
    my $value = $self->eval($ctx->{elem});
    last if $$ctx{abort};
    # Output text which preceeds the element
    my $prefix = '';
    if ($b > $$ctx{pos}) {
      my $pre_ws = $$ctx{collapse} ? leading(' \t', $ctx->{text}, $b, 1) : 0;
      my $width = $b - $$ctx{pos} - $pre_ws;
      $prefix = substr ${$$ctx{text}}, $$ctx{pos}, $width;
    }
    # If evaluation failed, use element definition
    if (defined $value) {
      $self->{'replace_count'}++;
    } else {
      my $def_text = substr(${$$ctx{text}}, $b, $ctx->{elem}{W});
      if ($self->{dbgout}) {
        ${$self->{dbgout}} = 'SIG_UNDEFINED';
        $value = delete $ctx->{elem}{value_override};
        $value = $def_text unless defined $value;
      } else {
        $value = $def_text;
      }
    }
    ${$$ctx{out}} .= $prefix;
    ${$$ctx{out}} .= isa($value, 'SCALAR') ? $$value : $value;
    # Increment position and continue
    my $post_ws = $$ctx{collapse} && !$ctx->{elem}{e_slurp}
      ? trailing('\r\n', $ctx->{text}, $ctx->{elem}->{E}, 1)
      : 0;
    $$ctx{pos} = $ctx->{elem}{e_slurp} || $ctx->{elem}{E} + $post_ws;
  }
  $self->_remove_context();
}

# ------------------------------------------------------------------------------
# eval - Evaluate the given element
# eval $elem
# ------------------------------------------------------------------------------

sub eval {
  use warnings FATAL => qw(recursion);
  my $self = shift;
  my $elem = shift;
  # First field is special as it may indicate a parser directive
  $elem->{fields} = Parse::Template::Arguments->new($elem->{t});
  return unless defined $elem->{fields}[0];
  $elem->{is_directive} = $elem->{fields}[0] =~ s/^$self->{ds}//;
  undef $self->get_ctx->{collapse};
  $self->_eval($elem);
}

sub _eval {
  my $self = shift;
  my $elem = shift;
  return unless @{$elem->{fields}};
  my $value = undef;
  if ($elem->{is_directive}) {
    $value = $self->eval_directive($elem);
  } else {
    $self->get_ctx->{collapse} = 0;
    my ($addr, $v, $args) = $self->eval_fields($elem->{fields});
    defined $v and $value = $self->value_compile(\$addr, $v, @$args);
  }
  # $value should be a string if it is defined
  if (defined $value && (my $esc = $self->get_ctx->{esc})) {
    $value =~ s/(?<!\\)([$esc])/\\$1/g;
  }
  $value;
}

sub eval_directive {
  my $self = shift;
  my $elem = shift;
  my $value = undef;
  my $fields = [@{$elem->{fields}}]; # copy
  my $name = shift @$fields;
  my $sub_idx = $name eq $self->{cs} ? 1 : 0;
  $name eq $self->{cs} and $name = shift @$fields;
  throw Error::Programatic unless defined $name;
  my $sub = $self->get_directive($name, $sub_idx) or return;
  if (isa($sub, 'CODE')) {
    # Here is where we would resolve each field before passing
    # to the directive. This however is not done because the
    # directive gets to inspect each field and determine if it
    # is a variable or not. We would also parse options.
    $value = &$sub($self, $name, @$fields);
    $self->get_ctx->{collapse} = defined $value
      unless defined $self->get_ctx->{collapse};
  }
  $value;
}

# ------------------------------------------------------------------------------
# eval_fields - Walk through fields locically returning the [uncompiled] value
#
# This routine does the work of processing the variable spec with consideration
# of the `x ? y : z`, `&&` and `||` operations. For instance:
#
#  a
#  a || b
#  t ? a : b
#  t ? f || a : b && c
#  f ? f || c : b && a
#
# See also: `src/test/perl/t-eval-fields.pl`
# ------------------------------------------------------------------------------

our %FIELD_OPERATORS = map {$_ => 1} qw(|| && ? :);

sub eval_fields {

  my $self = shift or die;
  my $fields_param = shift or return;
  my $fields = [@$fields_param]; # b/c we splice the array
  my $value = undef;
  my $token = undef;
  my $args = [];

  while (@$fields) {

    my $i = 1;
    for (; $i < @$fields; $i++) {
      exists $FIELD_OPERATORS{$fields->[$i]} and last;
    }
    @$args = splice @$fields, 0, $i;
    $token = shift @$args;

    # A raw array is created by Parse::Template::Arguments when a cluster (or group)
    # is created using '(' and ')'
    $value = ref($token) eq 'ARRAY' 
      ? Parse::Template::ArgumentStack->new($self, $token)->eval()
      : $self->get_value(\$token);

    my $next = shift @$fields;

    last unless defined $next;

    # Distill value when used logically
    defined $value and $value = $self->value_compile(\$token, $value, @$args);
    $value = '' unless defined $value; # [#c && 'okay'] must return '' when `c` is undef
    @$args = ();

    $next eq '||' and $value ? last : next;
    $next eq '&&' and $value ? next : last;
    $next eq '?'  and do {
      my $c = 1;
      my $i = 1;
      for (; $i < @$fields; $i++) {
        my $p = $fields->[$i];
        $p eq '?' ? $c++ : $p eq ':' ? $c-- : next;
        $c > 0 or last;
      }
      $value ? splice @$fields, $i : splice @$fields, 0, $i + 1;
      next;
    };

    warnf "Unexpected field: %s\n", $next;
    last;

  }

  wantarray ? ($token, $value, $args) : $value;

}

# ------------------------------------------------------------------------------
# get_compiled_value - Get a variable as a string and compile if necessary
# get_compiled_value \$addr
# ------------------------------------------------------------------------------

sub get_compiled_value {
  my $self = shift;
  my $addr = shift;
  my $value = $self->get_value($addr);
  return unless defined $value;
  $self->value_compile($addr, $value, @_);
}

sub value_compile {
  my $self = shift;
  my $addr = shift;
  my $value = shift;
  return $value if isa($value, FS('Directory')); # XXX See note in Standard.pm _eval_into
  my $value_str = $self->value_to_string($value, @_);
  return $value_str unless $value_str;
  return $value_str unless index($value_str, $self->{bs}) >= 0;
  my @use = ();
  my ($path, $scope) = ();
  my $name = addr_name($$addr);
  if (isa($value, 'Parse::Template::Content')) {
    $path = $value->{ctx}{path};
    $scope = $value->{scope};
#warn "Using $path for $name: $value_str\n";
  } else {
    # when specifying '/path/to/file.txt/data/key/subkey', the path context
    # is: '/path/to'
    $path = addr_parent($$addr);
    if ($path) {
      my $node = $self->get_value(\$path);
      while ($path && !isa($node, FS('Directory'))) {
        $path = addr_parent($path);
        $node = $self->get_value(\$path);
      }
    }
    push @use, $value if isa($value, 'HASH');
    $path ||= $self->get_ctx->{path};
  }
  my $out = '';
  if (@_) {
    my %args = @_;
    for (keys %args) {
      $args{$_} = $self->get_value(\$args{$_});
#warn ">>: $name, $_=$args{$_}\n$value_str\n";
    }
    push @use, \%args;
  }
  $self->use(@use);
  $self->_invoke(text => \$value_str, out => \$out, path => $path,
    name => $name, scope => $scope);
  $self->unuse;
  $out;
}

# ------------------------------------------------------------------------------
# get_value_str - Get a variable value as a string
# get_value_str \$addr
# See also: L</get_value>
# ------------------------------------------------------------------------------

sub get_value_str {
  my $self = shift;
  my $addr = shift or return;
  unless (ref($addr)) {
    my $copy = $addr;
    $addr = \$copy;
  }
  $self->value_to_string($self->get_value($addr), @_);
}

# ------------------------------------------------------------------------------
# value_to_string - Get the string representation of a value
# ------------------------------------------------------------------------------

sub value_to_string {
  my $self = shift;
  my $value = shift;
  return $value unless ref($value);
  if (isa($value, 'CODE')) {
    $value = $self->value_eval($value, @_);
  }
  return $$value if isa($value, 'SCALAR');
  return $value->to_string if can($value, 'to_string');
  Data::Hub::Courier::to_string($value);
}

sub value_eval {
  my $self = shift;
  my $value = shift;
  return $value unless ref($value);
  if (isa($value, 'CODE')) {
    my $params = Data::OrderedHash->new(@_);
    foreach my $k (keys %$params) {
      my $v = $params->{$k};
      my $vv = $self->get_value(\$v);
      $params->{$k} = isa($vv, 'CODE') ? $self->value_eval($vv) : $vv;
    }
    $value = &$value(%$params);
  }
  $value;
}

sub _addr_localize {
  my $self = shift;
  my $addr = shift or return;
  if ($$addr =~ /^\.+/) {
    my $path = $self->get_ctx->{path} || '';
#warn "> localize: $$addr in $path\n";
    $$addr = $path . '/' . $$addr if ($path)
  }
  $$addr = addr_normalize($$addr);
#warn "  becomes: $$addr\n";
  $self->_unesc($addr);
  $$addr;
}

# unescape quotes.  these get escaped when parsed as an inner value.
sub _unesc {
  my $self = shift;
  my $sref = shift;
  $$sref =~ s/\\(['"])/$1/g;
  $$sref;
}

sub dequote {
  my $self = shift;
  my $addr = shift;
  return unless defined $addr && defined $$addr && $$addr ne '';
  my $c = substr($$addr, 0, 1);
  if (ord($c) < 65 || ord($c) == 96) {
    is_numeric($$addr) and return $$addr;
    $$addr =~ s/^'(.*)'$/$1/ and return $self->_unesc($addr);
    $$addr =~ s/^`(.*)`$/$1/ and return $self->_addr_localize($addr);
    $$addr =~ s/^"(.*)"$/$1/;
    $self->_addr_localize($addr);
  }
  $$addr;
}

# ------------------------------------------------------------------------------
# get_value - Get a variable value
# get_value \$addr
# C<$addr> is passed by-reference because we will update it when applying
# local path information.
# ------------------------------------------------------------------------------

sub get_value {
  my $self = shift;
  my $spec = shift;
  return unless defined $spec && reftype($spec);
  my $addr = ref($$spec) ? $$spec : $spec;
  if (isa($addr, 'Parse::Template::CallbackArgument')) {
    if ($$addr[0] =~ s/^$self->{ds}//) {
      return sub {
        return $self->eval_directive({'fields' => $addr});
      };
    } else {
      return sub {
        my $value = undef;
        my ($k, $v, $args) = $self->eval_fields($addr);
        return $self->value_eval($v, @$args);
      };
    }
  }
  return $addr unless isa($addr, 'SCALAR');
  return if $$addr eq '';
  my $c = substr($$addr, 0, 1);
  if (ord($c) < 65 || ord($c) == 96) {
    is_numeric($$addr) and return $$addr;
    $$addr =~ s/^'(.*)'$/$1/ and return $self->_unesc($addr);
    $$addr =~ s/^`(.*)`$/$1/ and return $self->_addr_localize($addr);
    $$addr =~ s/^"(.*)"$/$1/;
    $self->_addr_localize($addr);
  }
  my $value = undef;
  my $sep_idx = index($$addr, '/');
  if ($sep_idx == 0) {
    for (@{$self->{'root_stack'}}) {
      $value = $sep_idx >= 0 ? $_->get($$addr) : $_->{$$addr};
      last if defined $value;
    }
  } else {
    for (@{$self->{ctx}}) {
      $value = $sep_idx >= 0 ? $_->{vars}->get($$addr) : $_->{vars}->{$$addr};
      last if defined $value;
    }
    if (!defined($value)) {
      my $len = @{$self->{stack}};
      my $skip_start = 0;
      my $skip_end = 0;
      if ($self->get_ctx->{scope}) {
        $skip_end = $len - $self->get_ctx->{scope};
        $skip_start = $len - $self->get_ctx->{orig_stack_sz};
      }
#warn "SCOPE: 0 ($skip_start/$skip_end) $len\n";
      for (my $i = 0; $i < $len; $i++) {
        next if ($i >= $skip_start && $i < $skip_end);
        my $ns = $self->{stack}->[$i];
        $value = $sep_idx >= 0 ? $ns->[0]->get($$addr) : $ns->[0]->{$$addr};
        if (defined $value) {
          if ($ns->[1]) {
            $$addr = addr_normalize($ns->[1] . '/' . $$addr);
          }
          last;
        }
      }
    }
  }
  $value;
}

# ------------------------------------------------------------------------------
# _slurp - Slurp the contents of for block-type directive
# _slurp $name
# _slurp $name, $to_eof
# _slurp $name, $to_eof, $to_eol
#
# If C<$to_eof> is a true value and an end directive is not found, C<_slurp>
# will read to the end of the template text.
#
# If C<$to_eol> is not defined, it is true, which means the newlines after
# the closing tag will be consumed.
# ------------------------------------------------------------------------------

sub _slurp {
  my $self = shift;
  my $name = shift or return;
  my $to_eof = shift;
  my $to_eol = defined $_[0] ? shift : 1;
  my $ctx = $self->get_ctx or throw Error::Programatic '$ctx';
  my $elem = $ctx->{elem} or throw Error::Programatic '$elem';
  my $b = $elem->{E} + trailing('\r\n', $ctx->{text}, $elem->{E}, 1);
  my ($e, $E) = $self->end_pos($ctx->{text}, $name, $b, $to_eof);
  if ($e >= 0) {

    # The end of the slurp includes (eats) the end tag.
    $elem->{e_slurp} = $E;

    # When the end tag begins a line such as:
    #     [#:end xxx]
    # ^--^
    #   '- we will remove this portion from the block
    $e -= leading(' \t', $ctx->{text}, $e, 1);

  } elsif ($to_eof) {

    # Slurping to the end of file
    $e = $ctx->{len};
    $elem->{e_slurp} = $e;

  } else {

    # Block does not have an end tag
    return;

  }

  if ($b > $elem->{E}) {
    $to_eol and $elem->{e_slurp} += trailing('\r\n', $ctx->{text}, $elem->{e_slurp}, 1);
  } else {
    $ctx->{collapse} = 0;
  }
  my $substr_w = $e - $b;
  my $substr = substr ${$ctx->{text}}, $b, $substr_w;
  \$substr;
}

# ------------------------------------------------------------------------------
# end_pos - Find the position of the corresponding end directive
#
# All directives nested SHOULD be either inline (they do not slurp) or blocks 
# (they have an end directive).
#
# All nested directives MUST also have their own end directive. This is not 
# currently the case, so we do our best. Take this scenario:
#
#   [#:set foo]
#     This is a block
#   [#:end set]
#
# Which is just fine. However, this is difficult:
#
#   [#:set foo]
#     [#:set bar = 'Bar']
#     This is a block
#   [#:end set]
#
# Because we don't know that the nested `:set` directive is inline. So, we ask
# for the `$to_eof` parameter. If this is true, then we will return the normal
# end position, that is -1 when nested occurences are not paired up. Otherwise
# we will return the end position of the *last* corresponding end directive.
# This is the best we can do without more information, and passing or garnering
# that information is considered too expensive an operation at this level.
#
# Provisions have been made only considering the `:set` and `:into` directives. 
# -Ryan 11/2012
# ------------------------------------------------------------------------------

sub end_pos {
  my $self = shift;
  my $text = shift;
  my $name = shift;
  my $pos = shift || 0;
  my $to_eof = shift;
  my $beg_str = $self->{bs} . $self->{ds} . $name;
  my $end_str = $self->{bs} . $self->{ds} . $self->{cs} . $self->{cs_sep} . $name . $self->{es};
  my $beg_len = length($beg_str);
  my $end_len = length($end_str);
  my $beg_p = index $$text, $beg_str, $pos;
  my $end_p = index $$text, $end_str, $pos;
  my $end_p2 = $end_p;
  while ($end_p > $beg_p && $beg_p >= 0) {
    # Inspect next char so '[#:foobar' isn't considered a nested '[#:foo' 
    my $c = substr $$text, $beg_p + $beg_len, 1;
    while ($c !~ /\s|$self->{es}/ && $beg_p >= 0) {
#warn "cannot use $beg_p, b/c of: $c\n";
      $beg_p = index $$text, $beg_str, $beg_p + $beg_len;
      last if $beg_p < 0;
      $c = substr $$text, $beg_p + $beg_len, 1;
    }
    last unless $end_p > $beg_p && $beg_p >= 0;
#warn "nested: $beg_str: $beg_p/$end_p\n";
    $beg_p = index $$text, $beg_str, $beg_p + $beg_len;
    $end_p = index $$text, $end_str, $end_p + $end_len;
    # Use the last-good end_p. This is a work-around for not knowing if nested
    # items use an end tag. (Like :set)
    $end_p2 = $end_p if $end_p > 0;
  }
#warn "endsat: $end_p\n";
  return $to_eof
    ? ($end_p, $end_p >= 0 ? $end_p + $end_len : -1)
    : ($end_p2, $end_p2 >= 0 ? $end_p2 + $end_len : -1);
}

# ------------------------------------------------------------------------------
# block_pos - Return the begin and end block positions
# block_pos \$text, $begin_marker, $end_marker, $start_pos
# Similar in spirit to L</substr_pos> except this routine uses regular
# expressions to ensure a nexted '[#abcd' does not count as a nested '[#ab' and
# this routine does not track all sub-indexes.
# ------------------------------------------------------------------------------

sub block_pos($$$$) {
  my $self = shift;
  my ($text, $beg, $end, $pos) = @_;
  my ($b, $beg_match, $e) = ();
  $beg =~ s/(\W)/\\$1/g;
  my $e_re = $self->{es};
  $e_re =~ s/(\W)/\\$1/g;
  $beg .= "(\\s|$e_re)";
  ($b, $beg_match) = index_match $$text, $beg, $pos;
  return if $b < 0;
  $b ||= $pos;
  my $block_b = $b + length($beg_match);
  $e = index $$text, $end, $b;
  my $b2 = undef;
  ($b2, $beg_match) = index_match $$text, $beg, $block_b;
  while ($b2 > $b && $b2 < $e && $e > $b) {
    $e = index $$text, $end, $e+length($end);
    ($b2, $beg_match) = index_match $$text, $beg, $block_b;
  }
  ($b, $e);
}

# ------------------------------------------------------------------------------
# substr_pos - Return positions of begin and end markers
# substr_pos \$text, $begin_marker, $end_marker, $start_pos
#
# This routine recognizes C<$begin_marker> and C<$end_marker> as a balanced
# pair.
#
# Example 1:
#
#   $begin_marker = [#
#   $end_marker   = ]
#   a [#b [#c] [#d]] e
#     ^            ^
#   returns [[2, 15]]
#
# Example 2:
#
#   $begin_marker = [#if
#   $end_marker   = [#end if]
#   [#if true]do something[#end if]
#   ^                     ^
#   returns [[0, 22]]
# ------------------------------------------------------------------------------
#|test(match)
#|use Parse::Template::Base;
#|my $p = new Parse::Template::Base;
#|my $text = '<<>>';
#|my @pos = $p->substr_pos(\$text, '<', '>', 0);
#|join ',', map {join '-', @$_} @pos;
#=0-3,1-2
# ------------------------------------------------------------------------------

sub substr_pos($$$$) {
  my $self = shift;
  my ($text, $beg, $end, $pos) = @_;
  my ($b, $e, @b, @e) = ();
  # Index begin/end pairs
  $b = index $$text, $beg, $pos;
  return if $b < 0;
  unshift @b, $b;
  $e = index $$text, $end, $b;
  my $b2 = index $$text, $beg, $b+length($beg);
  while ($b2 > $b && $b2 < $e && $e > $b) {
    unshift @b, $b2;
    unshift @e, $e;
    $e = index $$text, $end, $e+length($end);
    $b2 = index $$text, $beg, $b2+length($beg);
  }
  if ($e < 0) {
    $e = length($$text);
  }
  unshift @e, $e;
  # Return matching begin/end pairs
  my @result = ();
  while (@b) {
    $b = shift @b;
    $e = pop @e;
    unshift @result, [$b, $e];
  }
  @result;
}

# ------------------------------------------------------------------------------
# _padding - Get number of preceeding and trailing whitespace characters
# _padding \$text, $begin_index, $end_index
#
# Returns an array of widths: ($w1, $w2)
#
#   $w1 = Number of preceeding whitespace characters
#   $w2 = Number of trailing whitespace characters
#
# Returns an (0, 0) if non-whitespace characters are immediately found in the 
# preceeding or trailing regions.
#
# We will look up to 80 characters in front of the current position.
# ------------------------------------------------------------------------------

sub _padding {
  my $self = shift;
  my ($text, $pos, $end_pos) = @_;
  my ($prefix, $suffix, $starts_line) = ();
  if ($pos == 0) {
    $prefix = 0;
    $starts_line = 1;
  } else {
    for my $i (1 .. 80) {
      last if ($pos - $i) < 0;
      my $prev_c = substr $$text, $pos - $i, 1;
      last unless $prev_c =~ /\s/;
      $prefix = 0 if !defined $prefix;
      if (($prev_c eq "\r") || ($prev_c eq "\n")) {
        $starts_line = 1;
        if ($i > 1) {
          $prefix = $i - 1;
        }
        last;
      }
    }
  }
  if ($starts_line) {
    $suffix = 0;
    my $last_c = '';
    my $len = length($$text);
    for my $i (0 .. 1) {
      last if $end_pos >= $len;
      my $next_c = substr $$text, $end_pos + $i, 1;
      if ((($next_c eq "\r") || ($next_c eq "\n"))
        && ($next_c ne $last_c)) {
        $suffix++;
        $last_c = $next_c;
      } else {
        last;
      }
    }
  }
  return defined $prefix && defined $suffix
    ? ($prefix, $suffix)
    : (0, 0);
}

1;

__END__

=test(match,Hello World) # Simple replacement
  use Parse::Template::Standard;
  my $t = 'Hello [#name]';
  my $p = new Parse::Template::Standard();
  my $o = $p->compile_text(\$t, {name => 'World'});
  return $$o;
=cut

=test(match,Hello World) # Variable expansion
  use Parse::Template::Standard;
  my $t = 'Hello [#name]';
  my $p = new Parse::Template::Standard();
  my $o = $p->compile_text(\$t, {name => '[#next]', next => 'World'});
  return $$o;
=cut

=test(match,Hello World) # Nested elements
  use Parse::Template::Standard;
  my $t = 'Hello [#data/name]';
  my $p = new Parse::Template::Standard();
  my $o = $p->compile_text(\$t, {data => {name => 'World'}});
  return $$o;
=cut

=test(match,Hello World) # Dynamic expansion
  use Parse::Template::Standard;
  my $t = 'Hello [#[#name]]';
  my $p = new Parse::Template::Standard();
  my $o = $p->compile_text(\$t, {name => 'next', next => 'World'});
  return $$o;
=cut

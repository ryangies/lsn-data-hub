package Parse::Template::Standard;
use strict;
our $VERSION = 0.1;

use Perl::Module;
use base 'Parse::Template::Base';
use Data::Hub::Util qw(:all);
use Math::Symbolic;
use Error::Logical;
use Algorithm::KeyGen qw($KeyGen);
use Data::Format::JavaScript qw(js_format js_format_string);
use Parse::Template::Content;
use Parse::Template::ForLoop;
use Parse::Template::Directives::FileInfo;
use Parse::Padding qw(:all);
use Parse::StringTokenizer;
use Perl::Compare;
use Parse::Template::ArgumentStack;
use Data::Dumper;

our %Directives = (
  # Process
  'comment' => [\&_eval_comment],
  'into'    => [\&_eval_into],
  'use'     => [\&_eval_use, \&_eval_end_use],
  'set'     => [\&_eval_set],
  'unset'   => [\&_eval_unset],
  'define'  => [\&_eval_define],
  # Logic
  'if'      => [\&_eval_if],
  'elsif'   => [\&_eval_if],
  'else'    => [\&_eval_else],
  'for'     => [\&_eval_for],
  # Toolkit
  'exec'    => [\&_eval_exec],
  'filter'  => [\&_eval_filter],
  'dump'    => [\&_eval_dump],
  'finfo'   => Parse::Template::Directives::FileInfo->new(),
  'math'    => [\&_eval_math],
  # Strings
  'trim'    => [\&_eval_trim],
  'replace' => [\&_eval_replace],
  'substr'  => [\&_eval_substr],
  'sprintf' => [\&_eval_sprintf],
  'indent'  => [\&_eval_indent],
  'join'    => [\&_eval_join],
  'split'   => [\&_eval_split],
  'lc'      => {'*' => [\&_eval_lc], 'first' => [\&_eval_lc_first]},
  'uc'      => {'*' => [\&_eval_uc], 'first' => [\&_eval_uc_first]},
  # Time
  'strftime' => [\&_eval_strftime],
  # Deprecated
  'subst'   => [\&_eval_subst], # deprecated Mar 15 2012
);

use Parse::Template::Directives::Base64;
$Directives{'base64'} = Parse::Template::Directives::Base64->new();

# Common access to parts of an address

$Directives{'addr'} = {};

$Directives{'addr'}{'*'}[0] = 
$Directives{'addr'}{'normalize'}[0] = sub {
  addr_normalize($_[0]->get_value_str(\$_[2])) || '';
};

$Directives{'addr'}{'parent'}[0] = sub {
  addr_normalize(addr_parent($_[0]->get_value_str(\$_[2]))) || '';
};

$Directives{'addr'}{'name'}[0] = sub {
  addr_name($_[0]->get_value_str(\$_[2])) || '';
};

$Directives{'addr'}{'basename'}[0] = sub {
  addr_basename($_[0]->get_value_str(\$_[2])) || '';
};

$Directives{'addr'}{'ext'}[0] = sub {
  addr_ext($_[0]->get_value_str(\$_[2])) || '';
};

$Directives{'addr'}{'split'}[0] = sub {
  my @parts = addr_split($_[0]->get_value_str(\$_[2])) || [];
  return \@parts;
};

$Directives{'addr'}{'join'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my @addrs = ();
  for (@_) {
    my $v = $self->get_value_str(\$_);
    push @addrs, $v if defined $v;
  }
  addr_join(@addrs) || '';
};

# JSON formatting

$Directives{'json'} = {};
$Directives{'json'}{'*'}[0] =
$Directives{'json'}{'var'}[0] = sub {
  my $self = shift;
  my $opts = my_opts(\@_);
  my $value = $self->_get_data_value(@_, -opts => $opts);
  $self->get_ctx->{'collapse'} = 0;
  js_format($value, -opts => $opts);
};
$Directives{'json'}{'string'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  my $text = $self->get_compiled_value(\$addr);
  $self->get_ctx->{'collapse'} = 0;
  js_format_string($text);
};

sub _get_data_value {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  my $value = defined($addr) ? $self->get_value(\$addr) : $self->_slurp($name);
  $value = $self->value_eval($value, @_) if isa($value, 'CODE');
  if ($opts->{compile} && defined($value)) {
    if (isa($value, 'HASH') || isa($value, 'ARRAY')) {
      $value = curry(clone($value, -keep_order));
      $value->walk(sub {
        my ($key, $v, $depth, $addr, $parent) = @_;
        curry($parent);
        return unless defined $v;
        my $text = str_ref($v);
        return unless defined $text;
        my $out = '';
        $self->_invoke(text => $text, out => \$out);
        $parent->_set_value($key, $out);
      });
    } else {
      my $text = '';
      $self->_invoke(text => str_ref($value), out => \$text);
      $value = $text;
    }
  }
  return $value;
};

sub new {
  my $class = shift;
  my ($opts) = my_opts(\@_);
  my $self = $class->SUPER::new(-opts => $opts);
  @_ and push @{$$self{'root_stack'}}, @_;
  $self->set_directives(%Directives);
  $self;
}

# ------------------------------------------------------------------------------
# get_opts - Utility method to extract and dereference options
# ------------------------------------------------------------------------------

sub get_opts {
  my $self = shift;
  my $opts = my_opts(@_);
  foreach my $k (keys %$opts) {
    my $v = $opts->{$k};
    $opts->{$k} = $self->get_compiled_value(\$v);
  }
  return $opts;
}

# ------------------------------------------------------------------------------
# comment
# ------------------------------------------------------------------------------

sub _eval_comment {
  my $self = shift;
  my $name = shift;
  $self->_slurp($name);
  $self->get_ctx->{'collapse'} = 1;
  '';
}

# ------------------------------------------------------------------------------
# into
# ------------------------------------------------------------------------------
# Note, there's a little catch twenty-two here, we need to: a) parse the outer
# text ($into_str) first so that the order of events is logical; b) parse the 
# inner content first so that it is evaluated in this context, i.e., 
# './dir/file' paths resolve to the correct directory.
# ------------------------------------------------------------------------------

sub _eval_into {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  my %params = @_ ? @_ : ();
  # Resolve $addr parameter
  my $into = $self->get_value(\$addr) or return;
  my $into_addr = $addr;
  # If $addr resolved to an address, follow it.  $into may resolve to a
  # multipart structure, where it will be used as context data
  if ($into && !ref($into)) {
    my $real_into = $self->get_value(\$into);
    $into_addr = $into;
    $into = $real_into;
  }
  # Convert $into to parseable text
  my $into_str = $self->value_to_string($into);
  # Fetch the block which will *go into* $into_str
  my $block = $self->_slurp($name, 1);
  # Assign the block to its 'as' variable name
  my $as = 'CONTENT';
  if ($params{'as'}) {
    $as = delete $params{'as'};
    $self->dequote(\$as);
  }
  # Proxy the context for $block when needed (see note above)
  my $content = Parse::Template::Content->new(
    content => $block,
    ctx => $self->get_ctx,
    scope => scalar(@{$self->{stack}}),
  );
  # Resolve parameter values in this context
  #
  # XXX Often the cwd is passed like [#:into abc.txt _dir=./] and
  # we don't want _dir to be stringified. See note in Base.pm value_compile
  #
  foreach my $k (keys %params) {
    my $v = $params{$k};
    $params{$k} = $self->get_compiled_value(\$v);
#   $params{$k} = $self->get_value(\$v);
  }
  my $result = '';
  my $path = $self->get_ctx->{path} . '/' . $self->get_ctx->{name};
  $self->use($path => {$as => $content}, $into_addr => $into, \%params);
  $self->_invoke(text => \$into_str, out => \$result, name => addr_name($addr),
    path => addr_parent($self->_addr_localize(\$addr))
  );
  $self->unuse();
  $self->get_ctx->{'collapse'} = 0;
  \$result;
}

# ------------------------------------------------------------------------------
# use
# ------------------------------------------------------------------------------

sub _eval_use {
  my $self = shift;
  my $name = shift;
  for (@_) {
    my $v = $self->get_value(\$_);
    $v = $self->value_eval($v) if isa($v, 'CODE');
    $self->use($_ => $v);
  }
  $self->get_ctx->{'collapse'} = 1;
  '';
}

sub _eval_end_use {
  my $self = shift;
  $self->unuse();
  $self->get_ctx->{'collapse'} = 1;
  '';
}

# ------------------------------------------------------------------------------
# define - Define a variable
#   [#:define myvar] ... [#:end define]
#
# The difference between `define` and `set` is that `define` compiles the block
# when its encountered (under that context). This can also be acheived with
# `set -compile => 1`.
# ------------------------------------------------------------------------------

sub _eval_define {
  my $self = shift;
  my $name = shift;
  my $var_name = shift;
  my $value = '';
  $self->_invoke(text => $self->_slurp($name), out => \$value);
  $self->get_ctx->{vars}->set($var_name, $value);
  $self->get_ctx->{'collapse'} = 1;
  '';
}

# ------------------------------------------------------------------------------
# set - Set a local variable
#   [#:set myvar=myval]
#   [#:set mysub => subroutine, -noexec]
#
# !!! This needs to be depricated (b/c of nesting, finding the end_pos) and
# !!! moved to a directive `:set:block`
#
#   [#:set myvar] ... [#:end set]
#   [#:set myvar -compile] ... [#:end set]
# ------------------------------------------------------------------------------

our %SET_OPERATIONS = (
  '++' => sub { return $_[0] + 1 },
  '--' => sub { return $_[0] - 1 },
);

sub _eval_set {
  my $self = shift;
  my $opts = my_opts(\@_, {compile => 0, noexec => 0});
  my $name = shift;
  my $var_name = shift;
  my $var_ctx = undef;
  my $value = undef;
  if (@_) {
    my ($addr, $v, $args) = $self->eval_fields(\@_);
    $value = $v;
    if (isa($value, 'CODE') && !$$opts{'noexec'}) {
      $value = $self->value_eval($value, @$args);
    }
  } elsif (my $op = $SET_OPERATIONS{substr $var_name, -2}) {
    $var_name = substr $var_name, 0, -2;
    $var_ctx = $self->_get_var_ctx($var_name);
    $value = $var_ctx->{vars}->get($var_name);
    $value = &$op($value);
  } else {
    $value = $self->_slurp($name);
    $value and chomp $$value;
    if ($$opts{'compile'}) {
      # compile now (like :define)
      my $out = '';
      $self->_invoke(text => $self->_slurp($name), out => \$out);
      $value = $out;
    }
  }
  $var_ctx ||= $self->_get_var_ctx($var_name);
  $var_ctx->{vars}->set($var_name, $value);
  $self->get_ctx->{'collapse'} = 1;
  '';
}

sub _get_var_ctx {
  my $self = shift;
  my $var_name = shift;
  my $ctx = undef;
  for (@{$self->{ctx}}) {
    if (defined $_->{vars}->get($var_name)) {
      $ctx = $_;
      last;
    }
  }
  $ctx || $self->get_ctx;
}

# ------------------------------------------------------------------------------
# dump - Dump a variable value
# ------------------------------------------------------------------------------

sub _eval_dump {
  my $self = shift;
  my $name = shift;
  my $target = shift;
  my $value = $self->get_value(\$target);
  local $Data::Dumper::Terse = 1;
  local $Data::Dumper::Indent = 1;
  $self->get_ctx->{'collapse'} = 1;
  Dumper(clone($value, -pure_perl));
}

# ------------------------------------------------------------------------------
# exec - execute a subroutine
# ------------------------------------------------------------------------------

sub _eval_exec {
  my $self = shift;
  my $name = shift;
  my $target = shift;
  my $value = $self->get_value(\$target);
  $self->value_eval($value, @_);
  $self->get_ctx->{'collapse'} = 1;
  '';
}

# ------------------------------------------------------------------------------
# filter - execute a subroutine, passing the pre-parsed block contents
# ------------------------------------------------------------------------------

sub _eval_filter {
  my $self = shift;
  my $name = shift;
  my $target = shift;
  my $sub = $self->get_value(\$target);
  if (isa($sub, 'CODE')) {
    my $block = $self->_slurp($name, 1);
    my $contents = '';
    $$block and $self->_invoke(text => $block, out => \$contents);
    my $params = Data::OrderedHash->new(@_);
    foreach my $k (keys %$params) {
      my $v = $params->{$k};
      $params->{$k} = $self->get_value(\$v);
    }
    return &$sub(\$contents, %$params);
  } else {
    return undef;
  }
}

# ------------------------------------------------------------------------------
# unset
# ------------------------------------------------------------------------------

sub _eval_unset {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  return unless defined $addr;
  $self->get_ctx->{vars}->delete($addr);
  $self->get_ctx->{'collapse'} = 1;
  '';
}

# ------------------------------------------------------------------------------
# if/else
# ------------------------------------------------------------------------------

sub _eval_if {
  my $self = shift;
  my $name = shift;
  return unless @_;
#warn "eval $name:\n";
  my $block = $self->_slurp($name, 1);
  return '' unless $block;
#warn "$$block\n";
  # Find else point
  my $beg_str = $self->{bs} . $self->{ds} . 'if';
  my $end_str = $self->{bs} . $self->{ds} . $self->{cs} . ' if' . $self->{es};
  my $regions = $self->_find_regions($block, $beg_str, $end_str);
  my $else_str = $self->{bs} . $self->{ds} . 'els';
  my $else_p = index($$block, $else_str, 0);
  # Adjust for contained if blocks
  while ($else_p >= 0 && @$regions) {
    my $region = shift @$regions;
#warn "is $else_p > $$region[0] && < $$region[1]\n";
    if ($else_p > $$region[0] && $else_p < $$region[1]) {
      $else_p = index($$block, $else_str, $$region[1]);
    } else {
      next;
    }
  }
  # Adjust for padding
  my @trim = $self->_padding($block, $else_p, $else_p);
  my ($t_b, $t_e) = ($trim[0]);
  $else_p -= $t_b;
  # evaluate true/false
  my $stack = Parse::Template::ArgumentStack->new($self, [@_]);
  if ($stack->eval()) {
    if ($else_p >= 0) {
      my $substr = substr $$block, 0, $else_p;
      $block = \$substr;
    }
  } else {
    if ($else_p >= 0) {
      my $substr = substr $$block, $else_p;
      $block = \$substr;
    } else {
      $block = str_ref('');
    }
  }
  my $result = '';
  $$block and $self->_invoke(text => $block, out => \$result);
  \$result;
}

sub _eval_else {
  my $self = shift;
  my $name = shift;
  my $ctx = $self->get_ctx;
  $ctx->{elem}{e_slurp} = $ctx->{elem}{E}
    + trailing('\r\n', $ctx->{text}, $ctx->{elem}{E});
  '';
}

# ------------------------------------------------------------------------------
# Here's an idea, a common bit of recursive code could be presented like:
#
# [#:walk]
# <ol>
#   [#:item:begin]
#   <li>
#   [#:item:recurse]
#   </li>
#   [#:item:end]
# </ol>
# [#:end walk]
#
# This example would create nested OL for each nested item in a sitemap.
#
# Same code as the for loop, however the ->iterate (on each item) is replaced
# with ->walk, and also the block needs to split according to its :item:xxx
# markers...
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# for
#
#   [#:for items]
#   [#:for v in items]
#   [#:for (v) in items]
#   [#:for (k,v) in items]
#   [#:for (c,k,v) in items]
#   [#:for (c,k,v) in terms from definitions]
#
#   [#:for (c,k,v) in items of skeletons]       For content edititing, ce:for
#
# where:
#   
#   v           value
#   k           key (index when items is an array)
#   c           context (hash with members: index, number, and length)
#   items:      addr
#               addr [addr]...
#               (1 .. 10)
#               (a .. z)
#               CODE
#
# Obsolete (Mar 16 2012)
#
#   [#:for ([c,][k,]v) items]
#
# TODO: Refactor such that $block x= the number of items, create a tied hash
# which contains the size of the block and a list of items which is passed to
# $self->use.  When a value is fetched from the hash it uses this context's
# position to determine the correct value to return.
# ------------------------------------------------------------------------------

sub _eval_for {
  my $loop = new Parse::Template::ForLoop(@_);
  return $loop->compile();
# my $self = shift;
# my $args = $self->_eval_for_parse_args(@_);
# my $bundle = $self->_eval_for_fetch_items($$args{'targets'});
# $self->_eval_for_exec($args, $bundle);
}

# case a) [#:for ...]
# case b) [#:for v in ...]
# case c) [#:for (v) in ... ]
# case d) [#:for (k, v) in ... ]
# case e) [#:for (c, k, v) in ... ]
sub _eval_for_parse_args {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $result = {'opts' => $opts};
  my ($ctx_n, $var_n, $val_n) = ();

  # We don't know for sure if the argument is a target item or a context
  # parameter unless there is a 'in' keyword (not required)
  my @args = (); # Could be params or items
  my @items = (); # Known to be items
  for (my $i = 0; @_; $i++) {
    my $arg = shift;
    if ($arg eq 'in') {
#warn "--found 'in'\n";
      @items = @_;
      last;
    }
    push @args, $arg;
  }
  if (@items) {
    if (@args == 1) {
      my $ctx_vars = shift @args;
      if (isa($ctx_vars, 'ARRAY')) {
        # Parameter group (cases c, d, and e)
        ($val_n, $var_n, $ctx_n) = reverse @$ctx_vars;
#warn "--ctx is array\n";
      } else {
#warn "--ctx is bareword\n";
        # Bareword value name (case b)
        $val_n = $ctx_vars;
      }
    } elsif (@args > 1) {
#warn "--ctx is barewords\n";
        ($val_n, $var_n, $ctx_n) = reverse @args;
    }
  } else {
#warn "--ctx is missing\n";
    # There are no context parameters (case a)
    @items = @args;
    if (@items > 1 && isa($items[0], 'ARRAY')) {
      my $ctx = $self->get_ctx;
      my $hint = sprintf "\n%s\n", $$ctx{'elem'}{'t'};
      warn "Obsolete usage suspected: [#:for (...) ...], ",
        "you MUST specify the 'in' keyword when using context variables: ",
        $hint;
    }
  }
  $result->{'var_names'} = [$ctx_n, $var_n, $val_n];

  # Create a list of referenced structures
  for (@items) {
#warn "--item: $_\n";
    if (isa($_, 'Parse::Template::CallbackArgument')) {
#warn "--items in callback\n";
      push @{$result->{'targets'}}, $_;
      next;
    }
    my @list = isa($_, 'ARRAY') ? @$_ : ($_);
    if (@list == 3 && $list[1] eq '..') {
      # (1 .. 10) and ('a' .. 'z') constructs
      my $beg = $self->get_value(\$list[0]);
      my $end = $self->get_value(\$list[2]);
      @list = (curry([($beg .. $end)]));
    }
    push @{$result->{'targets'}}, @list;
  }

  # Slurp the contents of the for block
  my $block = $self->_slurp($name)
    or throw Error::Logical "Directive '$name' does not specify a block\n";
  $result->{'block'} = $block;

  return $result;
}

# Inflate each structure, creating a master list of defined items
sub _eval_for_fetch_items {
  my $self = shift;
  my $targets = shift;
  my $items = [];
  my $each_count = 0;
  my $result = {'length' => 0, 'items' => $items};
  foreach my $addr (@$targets) {
    my $is_static = ref($addr);
    my $item = $self->get_value(\$addr);
#warn "--unwrap $item\n";
    $item = &$item() if isa($item, 'CODE');
    next unless defined $item;
    unless (ref($item)) {
      $item = Data::Hub::Container->new({$each_count++, $item});
    }
    Data::Hub::Container::Bless($item);
    my $addr_base = addr_base($addr);
    push @$items, {
      'is_static' => $is_static,
      'addr' => defined $addr_base ? $addr_base : '~', # const items
      'item' => $item,
    };
    $$result{'length'} += $item->length;
  }
  return $result;
}

sub _eval_for_exec {
  my $self = shift;
  my $args = shift;
  my $bundle = shift;
  my $looper = shift; # optional (used in ce:for loops)
  my $opts = $$args{'opts'} || {};
  my $items = $$bundle{'items'};
  my ($ctx_n, $var_n, $val_n) = @{$args->{'var_names'}};
  my $block = $args->{block};
  my $result = '';
  my $regions = undef;
  my $loop_ctx = {
    index => -1,
    number => 0,
    length => $$bundle{'length'},
    opts => $opts,
  };
  my $struct = undef;
  my $create_loop_ctx =
    $ctx_n ? sub {
        # for (ctx,var,val) in /some/thing
        my $struct = shift;
        $loop_ctx->{'index'}++;
        $loop_ctx->{'number'}++;
        my $nsaddr = $struct->{'addr'} . '/' . $_[0] . '/...';
        return ($nsaddr => {
          $ctx_n => $loop_ctx,
          $var_n => $_[0],
          $val_n => $_[1],
        });
      }
    : $var_n ? sub {
        # for (var,val) in /some/thing
        my $struct = shift;
        my $nsaddr = $struct->{'addr'} . '/' . $_[0] . '/...';
        return ($nsaddr => {
          $var_n => $_[0],
          $val_n => $_[1],
        });
      }
    : $val_n ? sub {
        # for (val) in /some/thing
        my $struct = shift;
        my $nsaddr = $struct->{'addr'} . '/' . $_[0] . '/...';
        return ($nsaddr => {
          $val_n => $_[1],
        });
      }
    : sub {
        # for /some/thing
        my $struct = shift;
        my $nsaddr = $struct->{'addr'} . '/' . $_[0];
        return ($nsaddr => $_[1]);
      };
  foreach $struct (@$items) {
    die unless defined $struct->{'addr'};
    my $do_events = $looper && !$struct->{'is_static'};
    $do_events and $looper->on_begin($struct, \$result);
    $struct->{'item'}->iterate(sub {
      $self->use(&$create_loop_ctx($struct, @_));
      $do_events and $looper->on_each($_[0], \$result);
      my $ctx = $self->_invoke(text => $block, out => \$result, regions => $regions);
      $regions ||= $ctx->{regions};
      $self->unuse;
    });
    $do_events and $looper->on_end($struct, \$result);
  }
  \$result;
}

sub _eval_math {
  my $self = shift;
  my $name = shift;
  my $expr = shift or return;
  my $vars = Data::OrderedHash->new(@_);
  $expr = $self->get_compiled_value(\$expr);
  foreach my $k (keys %$vars) {
    $vars->{$k} = $self->get_compiled_value(\$vars->{$k});
    $vars->{$k} =~ s/^([0-9]+)[a-z]+$/$1/; # strip units (like 'px', 'em', etc.)
  }
  my $tree = Math::Symbolic->parse_from_string($expr);
  my ($sub) = Math::Symbolic::Compiler->compile_to_sub($tree, [keys %$vars]);
  $self->get_ctx->{'collapse'} = 0;
  $sub->(values %$vars);
}

# [#:trim 'abc def ghi' -chars=5]
# abc...
#
# [#:trim 'abc def ghi' -chars=5 -no_ellipsis=1]
# abc

sub _eval_trim {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  return unless defined $addr;
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  isa($str, 'SCALAR') and $str = $$str;
  if (is_numeric($opts->{chars})) {
    my $orig_len = length($str);
    $str = substr($str, 0, $opts->{chars});
    my $len = length($str);
    my $last_char = '';
    if ($len < $orig_len) {
      while ($len) {
        $last_char = substr $str, --$len, 1;
        my $pen_char = substr $str, $len-1, 1;
        next if $pen_char =~ /[:'"]/;
        last if $last_char =~ /\s/
      }
      $str = substr $str, 0, $len;
      $str .= '...' unless $opts->{no_ellipsis};
    }
  }
  $self->get_ctx->{'collapse'} = 0;
  \$str;
}

sub _eval_subst {
  carp 'Directive :subst has been deprecated, use :replace instead';
  goto &_eval_replace;
}

sub _eval_replace {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  return unless defined $addr;
  my $search = $self->get_compiled_value(str_ref(shift));
  my $replace = $self->get_compiled_value(str_ref(shift));
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  isa($str, 'SCALAR') and $str = $$str;
  if ($$opts{'all'}) {
    $str =~ s/$search/$replace/g;
  } else {
    $str =~ s/$search/$replace/;
  }
#warn "str=$str\n";
#warn "search=$search\n";
#warn "replace=$replace\n";
  $self->get_ctx->{'collapse'} = 0;
  \$str;
}

sub _get_lines {
  my $opts = my_opts(\@_, {
    keep_indent => 0,
  });
  my $self = shift;
  my $name = shift;
  my $value;
  my @values = ();
  my @lines = ();
  if (my $addr = shift) {
    $value = $self->get_value(\$addr);
    $value = $self->value_eval($value, @_) if isa($value, 'CODE');
    $value = curry($value);
  } else {
    $self->_invoke(text => $self->_slurp($name, 0, 0), out => \$value);
  }
  return unless defined $value;
  if (can($value, 'values')) {
    @values = $value->values;
  } else {
    if ($$opts{'keep_indent'}) {
      @values = split /[ \t\r]*\n[\r]*/, $value
    } else {
      @values = split /[ \t\r]*\n[ \t\r]*/, $value
    }
  }
  foreach my $line (map {scalar($_)} @values) {
    $line =~ s/^\s+// unless $$opts{'keep_indent'};
    $line =~ s/\s+$//;
    push @lines, $line;
  }
  @lines;
}

# [#:indent array]             indent values
# [#:indent hash]              indent values
# [#:indent scalar]            indent on newlines
# [#:indent ] ... [#:end indent] indent on newlines
#   -num_chars => 2
#   -char => ' '
#   -use_tabs => 1
sub _eval_indent {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_, {
    num_chars => 4,
    use_tabs => 0,
    char => ' ',
  });
  my $num_chars = int($$opts{'num_chars'});
  my $char = $$opts{'char'} || $$opts{'use_tabs'} ? "\t" : ' ';
  my $line_prefix = $char x= $num_chars;
  my @lines = $self->_get_lines($name, -keep_indent => 1, @_);
  $self->get_ctx->{'collapse'} = 0;
  $line_prefix . join("\n" . $line_prefix, @lines);
}

# [#:join ' ', array]             trims and joins values
# [#:join ' ', hash]              trims and joins values
# [#:join ' ', scalar]            trims and joins on newlines
# [#:join ' '] ... [#:end join]   trims and joins on newlines
sub _eval_join {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $joint = $self->get_value_str(str_ref(shift)) || '';
  my @lines = $self->_get_lines($name, @_);
  $self->get_ctx->{'collapse'} = 0;
  $joint =~ s/\\{1}r/\r/g;
  $joint =~ s/\\{1}n/\n/g;
  join($joint, @lines);
}

# [#:split ' ', scalar]
# [#:split ' '] ... [#:end split]
sub _eval_split {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $delim = $self->get_value_str(str_ref(shift)) || '\s';
  my $value;
  if (my $addr = shift) {
    $value = curry($self->get_value(\$addr));
  } else {
    $self->_invoke(text => $self->_slurp($name, 0, 0), out => \$value);
    chomp $value;
  }
  return unless defined $value;
  $self->get_ctx->{'collapse'} = 0;
  [split($delim, $value)];
}

sub _eval_substr {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  return unless defined $addr;
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  my @args = ();
  foreach my $arg (@_) {
    push @args, $self->get_compiled_value(\$arg);
  }
  isa($str, 'SCALAR') and $str = $$str;
  my $result = @args == 2
    ? substr $str, $args[0], $args[1]
    : substr $str, $args[0];
#warn join(';', ($str, @args, $result)), "\n";
  $self->get_ctx->{'collapse'} = 0;
  \$result;
}

sub _eval_sprintf {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $format = shift;
  return unless defined $format;
  $format = $self->get_compiled_value(str_ref($format));
  isa($format, 'SCALAR') and $format = $$format;
  my @args = ();
  while (@_) {
    my $arg = shift;
    my $s = $self->get_compiled_value(\$arg);
    push @args, isa($s, 'SCALAR') ? $$s : $s;
  }
#warn join '|', $format, @args;
  $self->get_ctx->{'collapse'} = 0;
  no warnings 'uninitialized';
  sprintf $format, @args;
}

sub _eval_lc {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  return unless defined $addr;
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  my $result = lc $str;
  $self->get_ctx->{'collapse'} = 0;
  \$result;
}

sub _eval_lc_first {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  return unless defined $addr;
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  my $result = lcfirst $str;
  $self->get_ctx->{'collapse'} = 0;
  \$result;
}

sub _eval_uc {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  return unless defined $addr;
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  my $result = uc $str;
  $self->get_ctx->{'collapse'} = 0;
  \$result;
}

sub _eval_uc_first {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  return unless defined $addr;
  my $str = $self->get_compiled_value(\$addr);
  return unless defined $str;
  my $result = ucfirst $str;
  $self->get_ctx->{'collapse'} = 0;
  \$result;
}

# ------------------------------------------------------------------------------
# Time
# ------------------------------------------------------------------------------

# :strftime
# :strftime 'alias'
# :strftime '%Y-%m-%d'
# :strftime -localtime
# :strftime -time => 'Sun, 30 Dec 1973 00:00:00 -0400'
# :strftime -time => '1973-12-30' -time-format => '%Y-%m-%d'
sub _eval_strftime {
  my $self = shift;
  my $name = shift;
  my $opts = $self->get_opts(\@_);
  my $spec = $self->get_value_str(ref $_[0] ? $_[0] : \$_[0]) if @_;
  $self->get_ctx->{'collapse'} = 0;
  return strftime($spec, -opts => $opts);
}

1;

__END__

$Directives{'escape'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  my $value = $addr ? \$self->get_value_str(\$addr) : $self->_slurp($name);
  return unless $value;
  my $bs = $self->{bs};
  my $bs_new = $self->{bs};
  $bs =~ s/(?<!\\)(\W)/\\$1/g;
  if ($opts->{ncr}) {
    $bs_new =~ s/(?<!\\)(\W)/'&#'.ord($1).';'/ge
  } else {
    $bs_new = $bs;
  }
#warn "value:$$value\n";
#warn "bs:$bs\n";
#warn "bs_new:$bs_new\n";
  $$value =~ s/$bs/$bs_new/g;
  $$value;
};

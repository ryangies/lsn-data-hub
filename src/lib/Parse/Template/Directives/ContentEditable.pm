package Parse::Template::Directives::ContentEditable;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use Error::Logical;
use Parse::Template::Directives::ContentEditable::ForLoop;
use base qw(Tie::StdHash);

our %Directives;

# ------------------------------------------------------------------------------
# FETCH - Return the handler which processes all tags
# ------------------------------------------------------------------------------

sub FETCH {
  my $d = $Directives{$_[1]};
  defined $d ? $d : [\&_create_element];
}

sub _innerHTML {
  my $parser = shift; # Instance of Parse::Template::Web
  my $opts = my_opts(\@_);
  my $addr = shift;
  my $value = shift;
  if (!length($value)) {
    $value = $$opts{'input'} ? '' : '<br class="stub"/>';
  }
  my $lsn_opts = join ';', map {
    my $v = $$opts{$_};
    $_ . "='" . $parser->get_value_str(\$v) . "'";
  } keys %$opts;
  return $parser->is_editing
    ? "<!--ce:ds=\"innerHTML=$addr;\" _lsn_opts=\"$lsn_opts\"-->$value"
    : $value;
}

# ------------------------------------------------------------------------------
# _create_element - Create content editable elements
# [#:ce:p mytext] == <p>[#:ce mytext]</p>
# ------------------------------------------------------------------------------

sub _create_element {
  my $parser = shift; # Instance of Parse::Template::Web
  $parser->get_ctx->{collapse} = 0;
  my (undef, $tag_name) = split ':', shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  my @attrs = $parser->_elem_attrs(\@_);
  my $value = $parser->get_compiled_value(\$addr);
  $value = $$value if (isa($value, 'SCALAR'));
  my $beg = join(' ', $tag_name, @attrs);
  my $end = $tag_name;
  my $innerHTML = _innerHTML($parser, $addr, $value, -opts => $opts);
  sprintf '<%s>%s</%s>', $beg, $innerHTML, $end;
}

# ce

$Directives{'*'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my $addr = shift;
  $parser->get_ctx->{collapse} = 0;
  my $value = $parser->get_compiled_value(\$addr);
  $value = $$value if (isa($value, 'SCALAR'));
  _innerHTML($parser, $addr, $value, @_);
};

# ce:paras - alias for [#:ce ... -paras='enforce']

$Directives{'paras'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my $addr = shift;
  $parser->get_ctx->{collapse} = 0;
  my $value = $parser->get_compiled_value(\$addr);
  $value = $$value if (isa($value, 'SCALAR'));
  _innerHTML($parser, $addr, $value, @_, -paras => "'enforce'");
};

# ce:input

sub _quote {
  my $value = shift;
  $value =~ s/(?<!\\)"/\\"/g;
  '"' . $value . '"';
}

$Directives{'input'}[0] = sub {
  my $parser = shift;
  $parser->get_ctx->{collapse} = 0;
  my $name = shift;
  my $addr = shift;
  my $opts = my_opts(\@_);
  my $value = $parser->get_compiled_value(\$addr);
  $value = $$value if (isa($value, 'SCALAR'));
  $value = '' unless defined $value;
  my %attrs = (
    'type' => 'text',
    'value' => $value,
  );
  if ($parser->is_editing) {
    my $lsn_opts = join ';', map {
      my $v = $$opts{$_};
      $_ . "='" . $parser->get_value_str(\$v) . "'";
    } keys %$opts;
    $attrs{'_lsn_opts'} = $lsn_opts;
    $attrs{'_lsn_ds'} = "value='$addr'";
  }
  my $attrs = join ' ', map {$_ . '=' . _quote($attrs{$_})} keys %attrs;
  "<input $attrs/>";
};

# ce:attrs

$Directives{'attrs'}[0] = sub {
  my $parser = shift;
  $parser->get_ctx->{collapse} = 0;
  my $name = shift;
  my @attrs = ();
  my $ds = '';
  my $edit_mode = $parser->is_editing;
  if (@_ == 1) {
    my $addr = shift;
    my $hash = $parser->get_value(\$addr);
    return unless isa($hash, 'HASH');
    $hash->iterate(sub {
      my ($k, $v) = @_;
      !$edit_mode && $k eq 'innerHTML' and return;
      my $vv = '';
      $parser->_invoke(text => \$v, out => \$vv);
      my $a = $addr . '/' . $k;
      push @attrs, "$k=\"$vv\"";
      $ds .= "$k='$a';";
    });
  } else {
    while (@_) {
      my ($k, $v) = (shift, shift);
      !$edit_mode && $k eq 'innerHTML' and next;
      my $vv = $parser->get_compiled_value(\$v);
      push @attrs, "$k=\"$vv\"";
      $ds .= "$k='$v';";
    }
  }
  my $value = join (' ', @attrs);
  return $edit_mode ? "$value _lsn_ds=\"$ds\"" : $value;
};

# ce:style

$Directives{'style'}[0] = sub {
  my $parser = shift;
  my $opts = my_opts(\@_);
  $parser->get_ctx->{collapse} = 0;
  my $name = shift;
  my @styles = ();
  my $ds = '';
  my $edit_mode = $parser->is_editing;
  if (@_ == 1) {
    my $addr = shift;
    my $hash = $parser->get_value(\$addr);
    return unless isa($hash, 'HASH');
    $hash->iterate(sub {
      my ($k, $v) = @_;
      my $vv = '';
      $parser->_invoke(text => \$v, out => \$vv);
      my $a = $addr . '/' . $k;
      push @styles, "$k:$vv;";
      $ds .= "$k='$a';";
    });
  } else {
    while (@_) {
      my ($k, $v) = (shift, shift);
      my $vv = $parser->get_compiled_value(\$v);
      push @styles, "$k:$vv;";
      $ds .= "$k='$v';";
    }
  }

  # Build result string
  my @result = (
    sprintf('style="%s"', join ('', @styles))
  );

  if ($edit_mode) {
    # Set tag name option
    $$opts{'tagName'} ||= "'$name'";
    # Pass options to the client-side content editor
    my $lsn_opts = join ';', map {
      my $v = $$opts{$_};
      $_ . "='" . $parser->get_value_str(\$v) . "'";
    } keys %$opts;
    push @result, sprintf('_lsn_ds="%s" _lsn_opts="%s"', $ds, $lsn_opts);
  }

  return join ' ', @result;
};

# ce:image

$Directives{'image'}[0] = sub {
  my $parser = shift;
  my $edit_mode = $parser->is_editing;
  $parser->get_ctx->{collapse} = 0;
  $parser->_mk_image(@_, -editable => $parser->is_editing);
};

# Create an anchor (A) element
#
# The data is an address to a hash which contains the attribute values:
#   [#:ce:anchor data/hash]
#   [#:ce:anchor data/hash alt='blah']
#
# Simple anchor where the content is the same as the href attribute:
#   [#:ce:anchor data/addr/href]
#   [#:ce:anchor data/addr/href alt='blah']
#
$Directives{'anchor'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my $addr = shift;
  $parser->get_ctx->{collapse} = 0;
  my @attrs = ();
  my $text = '';
  my $ds = '';
  my $hash = $parser->get_value(\$addr);
  if (isa($hash, 'HASH')) {
    $hash->iterate(sub {
      my ($k, $v) = @_;
      my $vv = '';
      $parser->_invoke(text => \$v, out => \$vv);
      my $a = $addr . '/' . $k;
      if ($k =~ /^href$/) {
        $vv = $parser->_mk_url($vv);
      }
      if ($k eq 'innerHTML') {
        $text = $vv;
      } else {
        push @attrs, "$k=\"$vv\"";
      }
      $ds .= "$k='$a';";
    });
  } elsif ($hash && !ref($hash)) {
    my $uri = $parser->_mk_url($hash);
    push @attrs, "href=$uri";
    $ds .= "href='$addr';";
    $text = $uri;
  }
  push @attrs, $parser->_elem_attrs(\@_);
  my $attr_str = join (' ', @attrs);
  $attr_str .= " _lsn_ds=\"$ds\"" if $parser->is_editing;
  return "<a $attr_str>$text</a>";
};

$Directives{'anchor2'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my %params = @_;
  $parser->get_ctx->{collapse} = 0;
  my @attrs = ();
  my $text = '';
  my $ds = '';
  foreach my $k (keys %params) {
    my $v = $params{$k};
    my $vv = $parser->get_compiled_value(\$v);
    if ($k eq 'href') {
      $vv = $parser->_mk_url($vv);
    } 
    if ($k eq 'innerHTML') {
      $text = $vv;
    } else {
      push @attrs, "$k=\"$vv\"";
    }
    $ds .= "$k='$v';" if ($v ne $vv);
  }
  my $attr_str = join (' ', @attrs);
  $attr_str .= " _lsn_ds=\"$ds\"" if $parser->is_editing;
  return "<a $attr_str>$text</a>";
};

# ce:for

$Directives{'for'}[0] = sub {
  my $loop = new Parse::Template::Directives::ContentEditable::ForLoop(@_);
  return $loop->compile();
};

# ce:bool

$Directives{'bool'}[0] = sub {
  my ($parser, $name, $addr) = (shift, shift, shift);
  my %vaddrs = @_;
  $parser->get_ctx->{collapse} = 0;
  my $cond = str_ref($parser->get_compiled_value(\$addr));
  my $logic = 'undef';
  if (defined $$cond) {
    $logic = $$cond;
    $logic = 'true' if $$cond && $$cond =~ /^(True|Yes|On)$/i;
    $logic = 'false' if !$$cond || $$cond =~ /^(False|No|Off)$/i;
  }
  my $vaddr = $vaddrs{$logic};
  $vaddr = $vaddrs{false} if (!defined($vaddr) && $logic eq 'undef');
  my $value = $vaddr
    ? str_ref($parser->get_compiled_value(\$vaddr))
    : $logic eq 'false'
      ? ''
      : $logic;
  return $parser->is_editing
    ? $value # TODO UI for editing
    : $value;
};

1;

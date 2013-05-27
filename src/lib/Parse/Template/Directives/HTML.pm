package Parse::Template::Directives::HTML;
use strict;
our $VERSION = 0;

use Perl::Module;
use Tie::Hash;
use base qw(Tie::StdHash);
use Error::Logical;
use Data::Hub::Util qw(:all);

our %Static_Directives = ();

# ------------------------------------------------------------------------------
# FETCH - Return the handler which processes all tags
# ------------------------------------------------------------------------------

sub FETCH {
  my $d = $Static_Directives{$_[1]};
  defined $d ? $d : [\&_tag];
}

# ------------------------------------------------------------------------------
# _tag - Create HTML elements
# [#:html:p mytext]
# ------------------------------------------------------------------------------

sub _tag {
  my $parser = shift; # Instance of Parse::Template::Web
  $parser->get_ctx->{collapse} = 0;
  my (undef, $tag_name) = split ':', shift;
  my $addr = shift;
  my $value = $parser->get_compiled_value(\$addr);
  return $value unless $tag_name;
# my @attrs = (['ds', "innerHTML='$addr';"]);
  my @attrs = ([]);
  for (@_) {
    my ($k, $v) = (shift, shift);
    push @attrs, [$k, $parser->get_compiled_value(\$v)];
  }
  my $result = "<$tag_name";
  ($result .= " $_->[0]=\"$_->[1]\"") for @attrs;
  $value = $$value if (isa($value, 'SCALAR'));
  $result .= ">$value</$tag_name>";
  $result;
}

# ------------------------------------------------------------------------------
# html:attr - Create editable attributes
# ------------------------------------------------------------------------------

$Static_Directives{'attr'}[0] = sub {
  my $parser = shift;
  $parser->get_ctx->{collapse} = 0;
  my $name = shift;
  my @attrs = ();
  if (@_ == 1) {
    my $addr = shift;
    my $hash = $parser->get_value(\$addr);
    return unless isa($hash, 'HASH');
    $hash->iterate(sub {
      my ($k, $v) = @_;
      my $a = $addr . '/' . $k;
      push @attrs, "$k=\"$v\"";
    });
  } else {
    while (@_) {
      my ($k, $v) = (shift, shift);
      my $vv = $parser->get_compiled_value(\$v);
      push @attrs, "$k=\"$vv\"";
    }
  }
  join (' ', @attrs);
};

# html:style

$Static_Directives{'style'}[0] = sub {
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

  return join ' ', @result;
};

# ------------------------------------------------------------------------------
# html:escape - Replace '<' and '>' with their numeric character entity codes
# ------------------------------------------------------------------------------

$Static_Directives{'escape'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my $addr = shift;
  my $value = undef;
  if ($addr) {
    $value = $parser->get_compiled_value(\$addr);
  } else {
    $parser->_invoke(text => $parser->_slurp($name), out => \$value);
  }
  return '' unless $value;
  $value =~ s/(?<!\\)([<>])/'&#' . ord($1) . ';'/eg;
  $value;
};

# ------------------------------------------------------------------------------
# html:url - Return a URL for the specified resource
# ------------------------------------------------------------------------------

$Static_Directives{'url'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  if ($opts->{resize}) {
    my $addr_str = $parser->get_value_str(\$addr) or return;
    my $resize_str = $parser->get_value_str($opts->{resize}) or
      throw Error::Logical 'Missing resize value:' . $opts->{resize};
    my $url = $parser->_mk_url($addr_str);
    return "$url?resize=$resize_str";
  }
  my $value = $parser->get_value_str(\$addr) or return;
  return $parser->_mk_url($value);
};

# ------------------------------------------------------------------------------
# html:image - Create an HTMLImage element for the specified resource
# ------------------------------------------------------------------------------

$Static_Directives{'image'}[0] = sub {
  my $parser = shift;
  $parser->get_ctx->{collapse} = 0;
  $parser->_mk_image(@_);
};

$Static_Directives{'nodeicon'}[0] = sub {
  my $parser = shift;
  my $name = shift;
  my $addr = shift;
  my $node = $parser->get_value(\$addr) or return;
# my $type = isa($node, FS('Node')) ? $node->get_type : typeof($node, $addr);
  my $type = typeof($addr, $node);
  my $url = "'/res/icons/16x16/nodes/$type.png'";
  $parser->get_ctx->{collapse} = 0;
  $parser->_mk_image($name, $url);
};

# Create an anchor (A) element
#
# The data is an address to a hash which contains the attribute values:
#   [#:html:anchor data/hash]
#   [#:html:anchor data/hash alt='blah']
#
# Simple anchor where the content is the same as the href attribute:
#   [#:html:anchor data/addr/href]
#   [#:html:anchor data/addr/href alt='blah']
#
$Static_Directives{'anchor'}[0] = sub {
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
  return "<a $attr_str>$text</a>";
};

1;

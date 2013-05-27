package Parse::Template::Web;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use base qw(Parse::Template::Standard);
use Data::Hub::Util qw(:all);
use WWW::Livesite::Args;
use WWW::Misc::Image qw(image_dims props_to_resize_str);
use Parse::Template::BBCode;
#use Text::WikiText;
#use Text::WikiText::Output::HTML;

#our $WikiText_Parser = Text::WikiText->new();

our %Directives = ();

use Parse::Template::Directives::Encode;
$Directives{'encode'} = Parse::Template::Directives::Encode->new();

use Parse::Template::Directives::HTML;
tie my %HTML_Directives, 'Parse::Template::Directives::HTML';
$Directives{'html'} = \%HTML_Directives;

use Parse::Template::Directives::JS;
$Directives{'js'} = Parse::Template::Directives::JS->new();

use Parse::Template::Directives::URI;
$Directives{'uri'} = Parse::Template::Directives::URI->new();

use Parse::Template::Directives::ContentEditable;
tie my %CE_Directives, 'Parse::Template::Directives::ContentEditable';
$Directives{'ce'} = \%CE_Directives;
#$Directives{'ce'} = Parse::Template::Directives::ContentEditable->new();

use Carp qw(cluck);

sub new {
  my $class = shift;
  my $Hub = shift or throw Error::MissingArg;
  throw Error::IllegalArg unless isa($Hub, 'Data::Hub');
  my $self = $class->SUPER::new($Hub, @_);
# warn Dumper($$self{'opts'});
# cluck ('How we got here');
  $self->set_directives(%Directives);
  $self->{'Hub'} = $Hub;
  $self->{'included'} = {};
  $self;
}

$Directives{'cgi'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $result = undef;
  my $opts = $self->get_opts(\@_);
  while (@_) {
    my $addr = shift;
    next unless defined $addr;
    my $key = $self->get_compiled_value(\$addr);
    next unless defined $key;
    my $cgi = $self->{Hub}->get("/sys/request/cgi");
    $result = $cgi->get_valid($key, -opts => $opts);
    next unless defined $result;
  }
  defined $result ? $result : '';
};

$Directives{'get'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $addr = shift;
  $self->is_editing ? undef : $self->get_compiled_value(\$addr); # XXX seems backward
};

# http:header - Add an HTTP header for output
#
#   [#:http:header 'Name' 'Definition']
#   [#:http:header 'Name' 'Definition' -override]
#
# When -override is given, existing headers with the same name
# are removed.

$Directives{'http'}{'header'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my ($var_key, $var_value) = (shift, shift);
  my $key = $self->dequote(\$var_key) or return;
  my $value = $self->get_compiled_value(\$var_value);
  if ($$opts{'override'}) {
    $self->_set_header($key, $value);
  } else {
    $self->_add_header($key, $value);
  }
  ''
};

# :http:no-cache - Absolutely no caching
#
#   [#:http:no-cache]
#
# A shortcut for:
#
#   [#:http:header 'Pragma' 'no-cache']
#   [#:http:header 'Cache-Control' 'no-cache, no-store, max-age=0']
#   [#:http:header 'Expires' '0']

$Directives{'http'}{'no-cache'}[0] = sub {
  my $self = shift;
  my $name = shift;
  $self->_set_header('Pragma', 'no-cache');
  $self->_set_header('Cache-Control', 'no-cache, no-store, max-age=0');
  $self->_set_header('Expires', '0');
  ''
};

sub _set_header {
  my $self = shift or die;
  my $key = shift or return;
  my $value = shift;
  my $headers = $self->{Hub}->{"/sys/response/headers"};
  if (isa($headers, 'WWW::Livesite::Headers')) {
    $$headers{$key} = [$value];
  } else {
    my $header = grep_first {$_->[0] eq $key} @$headers;
    if ($header) {
      $header->[1] = $value;
    } else {
      push @$headers, [$key, $value];
    }
  }
}

sub _add_header {
  my $self = shift or die;
  my $key = shift or return;
  my $value = shift || '';
  my $headers = $self->{Hub}->{"/sys/response/headers"};
  if (isa($headers, 'WWW::Livesite::Headers')) {
    $$headers{$key} = $value;
  } else {
    push @$headers, [$key, $value];
  }
}

$Directives{'head'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $addr = shift or return;
  my $varname = $self->get_compiled_value(\$addr);
  my $value = '';
  $self->_invoke(text => $self->_slurp($name), out => \$value);
  my $content = $self->{Hub}->{"/sys/response/head/$varname"} || '';
  $self->{Hub}->{"/sys/response/head/$varname"} = $content
    ? "$content\n$value"
    : $value;
  return '';
};

$Directives{'css'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $opts = $self->get_opts(\@_);
  my %args = @_;
  if ($args{'src'}) {
    my %attrs = ();
    foreach my $k (keys %args) {
      $attrs{$k} = $self->get_compiled_value(\$args{$k});
    }
    my $src = $self->_mk_url($attrs{'src'});
    delete $attrs{'src'};
    $attrs{'href'} = $src;
    my $links = $self->{Hub}->{"/sys/response/head/links/css"} ||= [];
    push @$links, \%attrs;
  } else {
    my $value = '';
    $self->_invoke(text => $self->_slurp($name), out => \$value);
    # Unique id (supresses multiple inclusion)
    my $uid = undef;
    if ($uid = $$opts{'uid'}) {
      # -uid trumps -once
    } elsif (my $once = $$opts{'once'}) {
      $uid = join(':',
        $self->get_value(str_ref('UID2')),
        $self->get_ctx->{'elem'}{'B'}
      );
    }
    if ($uid) {
      return '' if $$self{'included'}{$uid};
      $$self{'included'}{$uid} = 1;
    }
    my $content = $self->{Hub}->{"/sys/response/head/css"} || '';
    $self->{Hub}->{"/sys/response/head/css"} = $content
      ? "$content\n$value"
      : $value;
  }
  $self->get_ctx->{'collapse'} = 1;
  '';
};

$Directives{'bbcode'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  my $text = '';
  if ($addr) {
    $text = $self->get_compiled_value(\$addr);
  } else {
    $self->_invoke(text => $self->_slurp($name, 1), out => \$text);
  }
  return unless defined $text;
  $self->_bbcode_to_html($text, $opts);
};

# $Directives{'wikitext'}[0] = sub {
#   my $self = shift;
#   my $name = shift;
#   my $addr = shift;
#   my $text = '';
#   if ($addr) {
#     $text = $self->get_compiled_value(\$addr);
#   } else {
#     $self->_invoke(text => $self->_slurp($name, 1), out => \$text);
#   }
#   return unless defined $text;
#   $self->_wikitext_to_html($text);
# };

use Data::Format::Nml::Document;

$Directives{'nml'}[0] = sub {
  my $self = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;
  my $text = '';
  if ($addr) {
    $text = $self->get_compiled_value(\$addr);
  } else {
    $self->_invoke(text => $self->_slurp($name, 1), out => \$text);
  }
  return '' unless $text;
  $text =~ s/</&lt;/g;
  $text =~ s/>/&gt;/g;
  my $doc = Data::Format::Nml::Document->new($text);
  $doc->to_string;
};

sub _mk_url {
  my $self = shift;
  my $value = shift or return;
  my $add_slash = $value =~ /\/$/;
  if ($value =~ /^#/) {
    return $value;
  }
  if ($value !~ /^([a-z\+]+:)?\/\//) {
    my $path = $self->get_ctx->{path};
    if ($path && $value =~ /^\.+/) {
      $value = addr_normalize($path . '/' . $value);
    }
  }
  my ($uri, $query) = $value =~ /([^\?#]+)(.*)/;
  my ($prefix, $path) = $uri =~ /((?:[a-z\+]+:)?\/\/)?(.*)/;
  my @path = ();
  for (split /\//, $path) {
    $_ = '' unless defined;
    $_ = _uri_escape($_);
    push @path, $_;
  }
  my $suffix = @path ? join('/', @path) : '';
  if (!$prefix && $suffix =~ /^\//) {
    if (my $base_uri = $self->{'opts'}{'base_uri'}) {
      $prefix = $base_uri;
    }
  }
  my $result = $prefix || '';
  $result .= $suffix if $suffix;
  $result .= '/' if $add_slash;
  $result .= $query if $query;
  $result;
}

# sub _wikitext_to_html {
#   my $self = shift;
#   my $text = shift;
#   my $document = $WikiText_Parser->parse($text);
#   Text::WikiText::Output::HTML->new->dump($document);
# }

sub _bbcode_to_html {
  my $self = shift;
  my ($text, $opts) = @_;
  return unless defined $text;
  $opts ||= {};
  my $value = '';
  my $BBCodeParser = Parse::Template::BBCode->new($self->{Hub});
  $BBCodeParser->compile_text(ref($text) ? $text : \$text, -out => \$value);
  unless ($$opts{'nobr'}) {
    $value =~ s/(?<!br\/>)(\r?\n\r?)/<br\/>$1/g;
  }
  \$value;
}

# ------------------------------------------------------------------------------
# _elem_attrs - Format arguments as element attributes
# _elem_attrs \@_
# ------------------------------------------------------------------------------

sub _elem_attrs {
  my $parser = shift;
  my $args = shift;
  my @attrs = ();
  while (@$args) {
    my ($k, $v) = (shift @$args, shift @$args);
    my $vv = $parser->get_value(\$v);
    push @attrs, "$k=\"$vv\"";
  }
  return @attrs;
}

# ------------------------------------------------------------------------------
# is_editing - Is the page being rendered for an authorized editor
# ------------------------------------------------------------------------------

sub is_editing {
  my $parser = shift;
  defined $$parser{'opts'}{'is_editing'}
    and return $$parser{'opts'}{'is_editing'};
  $$parser{'opts'}{'is_editing'} =
    $parser->{'Hub'}{'/sys/user'} && $parser->{'Hub'}{'/sys/user'}->is_admin;
}

# ------------------------------------------------------------------------------
# _mk_image - Create attributes for an image and possibly a wrapping anchor
# _mk_image $src
# _mk_image \%attrs
#
# where:
#
#   $src              image url (src attribute)
#   %attrs            image attributes which invoke special behavior
#     $attrs{src}     image url (src attribute)
#     $attrs{resize}  requests the image be resized to WxH/wxh
#     $attrs{href}    the image is wrapped in an anchor
#     $attrs{target}  that anchor has a target
#
# options:
#
#   -resize     => $WxH/wxh
#   -max_width  => $num
#   -max_height => $num
#   -min_width  => $num
#   -min_height => $num
#
# Resize format is C<WxH/wxh> (read as max-width by max-height over min-width by
# min-height) in pixels.
#
#   100           width <= 100
#   100x          width <= 100
#   100x99        width <= 100, height <= 99
#   100x99/       width <= 100, height <= 99
#   100x99/10     10 <= width <= 100, height <= 99
#   100x99/10x    10 <= width <= 100, height <= 99
#   100x99/10x9   10 <= width <= 100, 9 <= height <= 99
#   /10           10 <= width
#   /10x          10 <= width
#   /10x9         10 <= width, 9 <= height
#
# Template options should take precedence over data options so that one may
# lock-down the flow of the page.
#
# The Livesite responder for images allows one to specify the resize parameter
# in the URL:
#
#   http://www.example.com/images/laura.jpg?resize=50x50
#
# However the server simply resizes the image to the nearest reasonable size, 
# Which means the image tag must include the exact width and height.
# ------------------------------------------------------------------------------

sub _mk_image {

  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $addr = shift;

  my @a_attrs = (); # for the anchor element
  my %attrs = @_;
  if (my $pid = $attrs{'pid'}) {
    my $vv = $parser->get_value(\$pid);
    push @a_attrs, "id=\"$vv\"";
    delete $attrs{'pid'};
  }
  my @img_attrs = $parser->_elem_attrs([%attrs]); # for the image element
  my $img_ds = ''; # content-editable data
  my $src = ''; # the src attribute

  my $hash = $parser->get_value(\$addr);
  if (isa($hash, 'HASH')) {
    foreach my $k (keys %$hash) {
      my $v = $$hash{$k};
#   $hash->iterate(sub {
#     my ($k, $v) = @_;
      my $vv = '';
      # any value may contain template vars
      $parser->_invoke(text => \$v, out => \$vv);
      my $a = $addr . '/' . $k;
      if ($k =~ /^(href|target|rev|rel)$/) {
        # belongs to anchor elem
        #
        # Considering a special value which supresses the href= generation...
        # $k eq 'href' && $v eq 'custom:disabled';
        #
        $vv = $parser->_mk_url($vv) if $k eq 'href';
        push @a_attrs, "$k=\"$vv\"";
      } else {
        # belongs to image elem
        if ($k eq 'src') {
          $src = $vv;
        } else {
          push @img_attrs, "$k=\"$vv\"";
        }
      }
      $img_ds .= "$k='$a';";
#   });
    }
  } elsif ($hash && !ref($hash)) {
    # default is the src attribute
    $src = $hash;
    $img_ds = "src='$addr';"
  } else {
    return;
  }

  # template options
  foreach my $k (keys %$opts) {
    my $v = $opts->{$k};
    $opts->{$k} = $parser->get_value_str(\$v);
  }

  # content-editable may not resize images with a static resize option
  my $user_can_resize = $$opts{'resize'} ? 0 : 1;

  $parser->_addr_localize(\$src);
  my @dims = ();
  my $url = $src;
  my $src_data = '';
  my $image_style = '';
  my ($scheme, $path) = $src =~ /((?:[a-z\+]+:)?\/\/)?(.*)/;
  if (!$scheme) {
    my $info = $parser->_image_info($src, -opts => $opts);
    if ($$info{'exists'}) {
      my ($w, $h) = ($$info{'width'}, $$info{'height'});
      @dims = ("width=\"$w\"", "height=\"$h\"");
      $url = $$info{'url'};
    }
    if (my $zoom = $$info{'zoom'}) {
      $src_data = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
      my $real_image_url = $parser->_mk_url($$info{'url'});
      my @styles = (
        sprintf('background-image:url(\'%s\')', $real_image_url),
        sprintf('background-size:%dpx %dpx', $$info{'width'}, $$info{'height'}),
        sprintf('background-position:%dpx %dpx', $$zoom{'x'}, $$zoom{'y'}),
      );
      push @img_attrs, sprintf('style="%s"', join(';', @styles));
      my ($w, $h) = ($$zoom{'width'}, $$zoom{'height'});
      @dims = ("width=\"$w\"", "height=\"$h\"");
    }
  }


  # Perform base-uri magic
  $url = $parser->_mk_url($url);

  # get it together
  my $a_str = join ' ', @a_attrs;
  my $img_src = $src_data || $url;
  my $img_str = join ' ', @dims, "src=\"$img_src\"", @img_attrs;
  if ($$opts{editable}) {
    $img_str .= " _lsn_ds=\"$img_ds\"";
    $img_str .= " _lsn_opts=\"resize='no-resize';\"" unless $user_can_resize;
  }

  return @a_attrs ? "<a $a_str><img $img_str/></a>" : "<img $img_str/>";

}

sub _image_info {
  my $parser = shift;
  my $src = shift;
  my $opts = my_opts(\@_);

  # src may be /images/laura.jpg?resize=10x9
  my ($res, $params) = split /\?/, _uri_unescape($src);
  if ($params) {
    my $args = WWW::Livesite::Args->new($params);
    # template options take precedence
    map { $$opts{$_} ||= $$args{$_} } keys %$args;
  }

  # so, let's get the width and height of this image
  my $exists = 0;
  my ($w, $h, $url, $zoom) = ();
  if (my $image = $parser->get_value(\$res)) {
    $image->refresh; # signal that we are accessing this file (important)
    ($w, $h, $zoom) = image_dims($image->get_path, -opts => $opts);
    my $resize_str = $opts->{'maxdpi'}
      ? '1600x1600'
      : $opts->{'resize'} || props_to_resize_str($opts);
    $url = $resize_str ? "$res?resize=$resize_str" : $res;
    $exists = 1;
  } else {
    # Track an attempt to access the image which adds its path to the 
    # dependency list. (Aug 15 2011 RRG)
    my $path = $parser->{Hub}->addr_to_path($res);
    $parser->{Hub}->fs_access_log->set_value($path, 0);
#warn "Adding missing-image dependency: $path\n";
  }

  return {
    'url' => $url,
    'exists' => $exists,
    'width' => $w,
    'height' => $h,
    'zoom' => $zoom,
  };
}

sub _uri_unescape {
  my $url = shift;
# Causing problems with filenames which have a '+' in them, and this MUST be
# removed. It was here to capture cases where the Live editor set the src of
# an image with a space in it using the `+` character. This MUST be 
# transliterated before this point...
# $url =~ tr/+/ /;
  $url =~ s/%([a-fA-F0-9]{2})/pack("C",hex($1))/eg;
  $url;
}

sub _uri_escape {
  my $str = shift;
  $str =~ s/([^\${}A-Za-z0-9_\.-])/sprintf("%%%02X", ord($1))/eg;
  $str;
}

1;

__END__

package WWW::Misc::Image;
use strict;
our $VERSION = 0;

use base qw(Exporter);
use Perl::Module;
use Error::Programatic;
use Error::Logical;
use Data::Hub qw($Hub);
use Data::Hub::Util qw(:all);
use Perl::Options qw(my_opts);
use Image::Size qw();
use Try::Tiny;

# ------------------------------------------------------------------------------
# Detecting image dimensions
#
# This is very very slow...
#
#   my $image = GD::Image->new($path) or warn "Cannot create GD::Image ($@): $path";
#   return () unless $image;
#   $image->getBounds();
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Detect GD support
# ------------------------------------------------------------------------------

our $HAS_GD = 0;
try {
  require GD;
  $HAS_GD = 1;
} catch {
  # GD not found, image manipulation disabled
};

our @EXPORT_OK = qw(
  props_to_resize_str
  resize_str_to_props
  image_convert
  image_dims
  image_size
);

sub imgsize { goto image_size; }

sub image_size {
  my $path = shift or return ();
  return Image::Size::imgsize($path);

}

# ------------------------------------------------------------------------------
# image_convert - Create a file which satisfies the specified geometry
# image_convert $path, [options]
#
# options: See L</image_dims>
#
#   -out_dir    => $abs_path      # default is same dir as $path
#   -grayscale  => 1              # convert to grayscale
#   -watermark  => <Hash>         # watermark image
#   -maxdpi     => 1              # keep original image path/size
#   -resize    => WxH/wxh         # Resize to max W by H and min w by h
#
# ------------------------------------------------------------------------------

sub image_convert {
  my $path = shift or throw Error::Programatic "Provide a path";
  my ($opts) = my_opts(\@_);
  my ($orig_w, $orig_h) = image_size($path);
  my ($display_w, $display_h, $zoom_info) = image_dims($path, -opts => $opts);
  $$opts{'limits'} = [64, 200, 400, 800, 1680, 2048];
  my ($w, $h) = $$opts{'maxdpi'}
    ? ($orig_w, $orig_h)
    : image_dims($path, -opts => $opts);

  my $do_convert =
      ($w != $orig_w) ||
      ($h != $orig_h) ||
      $opts->{'grayscale'} ||
      $opts->{'watermark'};

  if ($do_convert) {
    my $out_dir = $opts->{'out_dir'} || path_parent($path);
    my $out_fn = _mkoutfn($opts, $path, $w, $h);
    my $new_path = path_normalize("$out_dir/$out_fn");
    if ($HAS_GD && (! -e $new_path || stat($path)->mtime > stat($new_path)->mtime)) {
      GD::Image->trueColor(1);
      my $ext = path_ext($new_path);
      my $src = GD::Image->new($path) or die $@;
      my $out = GD::Image->new($w, $h, 1); # true color (24bit)
      my $color_index = $src->transparent;
      $out->alphaBlending(0);
      $out->saveAlpha(1);
      $out->copyResampled($src, 0, 0, 0, 0, $w, $h, $orig_w, $orig_h);
      if (my $wm = $$opts{'watermark'}) {
        my $wm_path = $$wm{'path'} || $Hub->get($$wm{'image'})->get_path;
        my $wm_image = GD::Image->new($wm_path) or die $@;
        my ($wm_orig_w, $wm_orig_h) = $wm_image->getBounds();
        my ($wm_w, $wm_h) = image_dims($wm_path, -max_x => $w / 2, -max_y => $h / 2);
        my ($x, $y) = (0, 0); # Watermark position
        my ($pos_y, $pos_x) = split ' ', $$wm{'position'} || '';
        $pos_y ||= 'top';
        $pos_x ||= 'left';
        if ($pos_y eq 'middle') {
          $y = ($h / 2) - ($wm_h / 2);
        } elsif ($pos_y eq 'bottom') {
          $y = $h - $wm_h;
        }
        if ($pos_x eq 'center') {
          $x = ($w / 2) - ($wm_w / 2);
        } elsif ($pos_x eq 'right') {
          $x = $w - $wm_w;
        }
        $out->alphaBlending(1);
        $out->copyResampled($wm_image, $x, $y, 0, 0, $wm_w, $wm_h, $wm_orig_w, $wm_orig_h);
        $color_index ||= $wm_image->transparent;
      }
      if ($color_index >= 0) {
        $out->transparent($color_index);
        $out->interlaced(1);
      }
      my $blob =  $ext =~ /gif/i    ? $out->gif   :
                  $ext =~ /jpe?g/i  ? $out->jpeg  :
                  $ext =~ /png/i    ? $out->png   :
        throw Error::Logical "[Image Resize] Unsupported file type: $ext";
      file_write_binary($new_path, $blob);
    }
    $path = $new_path;
  }

  return {
    'path'    => $path,
    'width'   => $w,
    'height'  => $h,
    'display_width'   => $display_w,
    'display_height'  => $display_h,
    'zoom_info' => $zoom_info,
  };

}

use Parse::Template::Standard;
our $Parser = Parse::Template::Standard->new(
  -begin => '<',
  -end => '>',
);

# Output filename MUST as unique as the options!
sub _mkoutfn {
  my ($opts, $path, $w, $h) = @_;
  $opts->{'out_fn'} and return $opts->{'out_fn'};
  my $fmt = $opts->{'out_fn_fmt'} || ".<width>x<height>.<basename>.<ext>";
  my $props = {
    width => $w,
    height => $h,
    dir => path_parent($path),
    basename => path_basename($path),
    ext => path_ext($path),
  };
  # HACK - The options (like grayscale, watermark) indicate uniqueness. They are
  # used to create a checksum which is appended to the basename, rather than 
  # their own key, so to work with existing formats.
  $$props{'basename'} .= '_' . checksum(sort keys %$opts);
  my $out = $Parser->compile_text(\$fmt, $props);
  $$out;
}

# ------------------------------------------------------------------------------
# resize_str_to_props - Translate a resize string into a hash
#
# A resize string like this:
#
#     800x600/480x320
#
# Becomes
#
#     max_x => 800
#     max_y => 600
#     min_x => 480
#     min_y => 320
#
# Resize strings may omit dimensions, in which case they will default to zero
#
#     800                   max_x => 800
#     800x600               max_x => 800, max_y => 600
#     800x600/480           max_x => 800, max_y => 600, min_x => 480
#     800/480               max_x => 800, min_x => 480
#
# A shorthand of a single number ending with a caret (^) indicates all the
# dimensions are the same, and we a producing a zoomed (as opposed to a 
# letter-box image).
#
#     100^                  same as 100x100/100x100
#
# ------------------------------------------------------------------------------
#|test(!abort) use WWW::Misc::Image qw(resize_str_to_props);
#|test(match)
#|my $props = resize_str_to_props('800');
#|join(';', map { $_ . '=' . $$props{$_} } sort keys %$props);
#=max_x=800;max_y=0;min_x=0;min_y=0
#|test(match)
#|my $props = resize_str_to_props('800x600');
#|join(';', map { $_ . '=' . $$props{$_} } sort keys %$props);
#=max_x=800;max_y=600;min_x=0;min_y=0
#|test(match)
#|my $props = resize_str_to_props('800x600/480');
#|join(';', map { $_ . '=' . $$props{$_} } sort keys %$props);
#=max_x=800;max_y=600;min_x=480;min_y=0
#|test(match)
#|my $props = resize_str_to_props('800/480');
#|join(';', map { $_ . '=' . $$props{$_} } sort keys %$props);
#=max_x=800;max_y=0;min_x=480;min_y=0
#|test(match)
#|my $props = resize_str_to_props('100/z');
#|join(';', map { $_ . '=' . $$props{$_} } sort keys %$props);
#=flags=z;max_x=100;max_y=0;min_x=0;min_y=0
# ------------------------------------------------------------------------------

sub resize_str_to_props {
  my $resize = shift;
  my $result = {};
  my @max_xy = ();
  my @min_xy = ();
  my ($max,$min) = split '/', $resize;
  @max_xy = $max ? split('x', $max) : ();
  if ($min && $min =~ /[A-Za-z]+/) {
    $result->{'flags'} = $min;
  } else {
    @min_xy = $min ? split('x', $min) : ();
  }
  $result->{'max_x'} = $max_xy[0] || 0;
  $result->{'max_y'} = $max_xy[1] || 0;
  $result->{'min_x'} = $min_xy[0] || 0;
  $result->{'min_y'} = $min_xy[1] || 0;
  $result;
}

# ------------------------------------------------------------------------------
# props_to_resize_str - Create a resize-string from hash properties.
#
# This is the inverse of L<resize_str_to_props>.
# ------------------------------------------------------------------------------
#|test(!abort) use WWW::Misc::Image qw(props_to_resize_str);
#|test(match,800) props_to_resize_str({max_x => 800});
#|test(match,800x600) props_to_resize_str({max_x => 800, max_y => 600});
#|test(match,800/480) props_to_resize_str({max_x => 800, min_x => 480});
#|test(match,100x100/100x100)
#|props_to_resize_str({max_x => 100, max_y => 100,min_x => 100, min_y => 100});
#|test(match,100/z)
#|props_to_resize_str({max_x => 100, flags => 'z'});
# ------------------------------------------------------------------------------

sub props_to_resize_str {
  my $props = shift or return;
  my $result = '';
  $$props{'max_x'} ||= 0;
  $$props{'max_y'} ||= 0;
  $$props{'min_x'} ||= 0;
  $$props{'min_y'} ||= 0;
  $result .= $$props{'max_x'} if $$props{'max_x'};
  $result .= 'x' . $$props{'max_y'} if $$props{'max_y'};
  if ($$props{'min_x'} || $$props{'min_y'}) {
    $result .= '/';
    $result .= $$props{'min_x'} if $$props{'min_x'};
    $result .= 'x' . $$props{'min_y'} if $$props{'min_y'};
  } elsif (my $flags = $$props{'flags'}) {
    $result .= "/$flags";
  }
  $result;
}

sub has_flag {
  my $props = shift or return;
  my $flag = shift or return;
  my $flags = $$props{'flags'} or return;
  $flags =~ /$flag/;
}

# ------------------------------------------------------------------------------
# image_dims - Get image dimensions
# image_dims $path, [options]
#
# options:
# 
#   -resize=WxH/wxh   Resize to max W by H and min w by h
#   --or--
#   -max_x=n          Maximum width
#   -max_y=n          Maximum height
#   -min_x=n          Minimum width
#   -min_y=n          Minimum height
#
#   my ($w,$h) = image_dims( "/images/laura.jpg", -max_x => 50, -max_y => 50 );
#   my ($w,$h) = image_dims( "/images/laura.jpg", -resize => '50x50' );
#
# Zoomed image:
#
#   my ($w,$h,$z) = image_dims( "/images/laura.jpg", -resize => '50^' );
#
# ------------------------------------------------------------------------------
#|test(!abort) use WWW::Misc::Image qw(image_dims);
#|test(false) image_dims("/foo");
# ------------------------------------------------------------------------------

sub image_dims {

  my ($opts, $file) = my_opts(\@_);

  my $nx = 0;
  my $ny = 0;
  my $w = 0;
  my $h = 0;

  ($nx,$ny) = image_size($file);

  my $resize_str = $opts->{'resize'};

  return ($nx, $ny) if $resize_str && $resize_str eq '1:1';

  my $dims = $resize_str
    ? resize_str_to_props($resize_str)
    : $opts;

  $dims->{'max_x'} ||= 0;
  $dims->{'min_x'} ||= 0;
  $dims->{'max_y'} ||= 0;
  $dims->{'min_y'} ||= 0;

  $w = $nx;
  $h = $ny;

  return unless defined $nx && defined $ny;

  if (my $limits = $opts->{'limits'}) {

    my $max_x = 0;
    my $max_y = 0;
    my $min_x = 0;
    my $min_y = 0;

    my @x_limits = sort {$a <=> $b} (@$limits, $w);
    my @y_limits = sort {$a <=> $b} (@$limits, $h);

    for (@x_limits) {
      $max_x ||= $_ if $_ > $dims->{'max_x'} && $dims->{'max_x'};
      $min_x ||= $_ if $_ > $dims->{'min_x'} && $dims->{'min_x'};
    }

    for (@y_limits) {
      $max_y ||= $_ if $_ > $dims->{'max_y'} && $dims->{'max_y'};
      $min_y ||= $_ if $_ > $dims->{'min_y'} && $dims->{'min_y'};
    }

    $dims->{'max_x'} = $max_x;
    $dims->{'max_y'} = $max_y;
    $dims->{'min_x'} = $min_x;
    $dims->{'min_y'} = $min_y;

  }

  # Zoomed (square) image
  if (has_flag($dims, 'z')) {
    my $target_w = $$dims{'max_x'};
    my $target_h = $$dims{'max_y'} || $$dims{'max_x'}; # Default is square zoom
    die unless $target_w > 0 && $target_h > 0;
    my $scale_by_w = $target_w / $w;
    my $scale_by_h = $target_h / $h;
    if ($scale_by_w > $scale_by_h) {
      $nx = $target_w;
      $ny = int($h * $scale_by_w);
    } else {
      $nx = int($w * $scale_by_h);
      $ny = $target_h;
    }
    my $offset_x = int(($target_w - $nx) / 2);
    my $offset_y = int(($target_h - $ny) / 2);
    my $zoom_info = {
      'width' => $target_w,
      'height' => $target_h,
      'x' => $offset_x,
      'y' => $offset_y,
    };
    return ($nx, $ny, $zoom_info);
  }

  # Reduce
  if( $$dims{'max_x'} > 0 ) {
    if( $nx > $$dims{'max_x'} ) {
      my $ratio = $ny/$nx;
      my $reduceX = $nx - $$dims{'max_x'};
      my $reduceY = int($reduceX*$ratio);
      $w = $nx - $reduceX;
      $h = $ny - $reduceY;
      $nx = $w;
      $ny = $h;
    }
  }
  if( $$dims{'max_y'} > 0 ) {
    if( $ny > $$dims{'max_y'} ) {
      my $ratio = $nx/$ny;
      my $reduceY = $ny - $$dims{'max_y'};
      my $reduceX = int($reduceY*$ratio);
      $w = $nx - $reduceX;
      $h = $ny - $reduceY;
      $nx = $w;
      $ny = $h;
    }
  }

  # Expand
  if( $nx > 0 && $$dims{'min_x'} > 0 ) {
    if( $nx < $$dims{'min_x'} ) {
      my $ratio = $ny/$nx;
      my $expandX = $$dims{'min_x'} - $nx;
      my $expandY = int($expandX*$ratio);
      if ($$dims{'max_y'} && ($ny + $expandY) <= $$dims{'max_y'}) {
        $w = $nx + $expandX;
        $h = $ny + $expandY;
        $nx = $w;
        $ny = $h;
      }
    }
  }
  if( $ny > 0 && $$dims{'min_y'} > 0 ) {
    if( $ny < $$dims{'min_y'} ) {
      my $ratio = $nx/$ny;
      my $expandY = $$dims{'min_y'} - $ny;
      my $expandX = int($expandY*$ratio);
      if ($$dims{'max_x'} && ($nx + $expandX) <= $$dims{'max_x'}) {
        $w = $nx + $expandX;
        $h = $ny + $expandY;
        $nx = $w;
        $ny = $h;
      }
    }
  }

  return ($nx, $ny);
}

1;

__END__

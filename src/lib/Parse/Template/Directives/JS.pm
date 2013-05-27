package Parse::Template::Directives::JS;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Format::XFR;
use Data::Hub::Util qw(:all);

our $Xfr = Data::Format::XFR->new('base64');

#
# XXX Changes made to the /sys/response/head need to be reflected
# in js.lsn.includeHeadJS
#

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {
    'var'     => [\&_js_var],
    'extend'  => [\&_js_extend],
    'src'     => [\&_js_src],
    'event'   => [\&_js_event],
    'closure' => [\&_js_closure],
    'global'  => [\&_js_global],
    '*'       => [\&_js],
  }, $class;
}

# :js:var /data/colors.hf
sub _js_var {
  my $parser = shift;
  my $value = $parser->_get_data_value(@_);
  'js.data.xfr.parse(\'' . $Xfr->format($value) . '\')';
}

# :js:extend 'local'
#   ...
# :end js:extend
sub _js_extend {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_, {inline => 0});
  my $spec = shift;
  my $value = '';
  if (my $block = _my_slurp($parser, $name, $opts)) {
    $parser->_invoke(text => $block, out => \$value);
    my $ns = $parser->get_value_str(\$spec);
    my $content = $parser->{Hub}->{"/sys/response/head/extend/js/$ns"} || '';
    $parser->{Hub}->{"/sys/response/head/extend/js/$ns"} = "$content\n$value";
  }
  $parser->get_ctx->{'collapse'} = 1;
  '';
}

# :js:src '/res/js/livesite.js'
# :js:src '/res/js/livesite.js' -priority
sub _js_src {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_, {inline => 0});
  my $src = shift;
  my %args = @_;
  my %attrs = ();
  foreach my $k (keys %args) {
    $attrs{$k} = $parser->get_compiled_value(\$args{$k});
  }
  $attrs{'type'} ||= 'text/javascript';
  $attrs{'src'} = $parser->_mk_url($parser->get_compiled_value(\$src));
  if ($$opts{'inline'}) {
    # By setting this `have_linked` semiphore, the normal responder will suppress
    # this URL from being emitted should it also be inlcuded in a non-inline
    # js directive.
    my $have_linked = $parser->{Hub}->{"/sys/response/head/have_linked"} ||= {};
    $$have_linked{$attrs{'src'}} = 1;
    my $attr_str = join ' ', map {$_ . '=' . _quote($attrs{$_})} sort keys %attrs;
    $parser->get_ctx->{'collapse'} = 0;
    return "<script $attr_str></script>";
  } else {
    my $links = $parser->{Hub}->{"/sys/response/head/links/js"} ||= [];
    push @$links, \%attrs;
  }
  $parser->get_ctx->{'collapse'} = 1;
  '';
}

# :js:event 'window,load'
#   ...
# :end js:event
sub _js_event {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $event = shift;
  my $value = '';
  if (my $block = _my_slurp($parser, $name, $opts)) {
    $parser->_invoke(text => $block, out => \$value);
    my ($target, $event_name)
      = split /[\s;,]\s*/, $parser->get_value_str(\$event);
    $parser->{Hub}->{"/sys/response/head/events/js/$target/<next>"} = {
      key => $event_name,
      value => $value,
    };
  }
  $parser->get_ctx->{'collapse'} = 1;
  '';
}

# :js:closure
#   ...
# :end js:closure
sub _js_closure {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $value = '';
  if (my $block = _my_slurp($parser, $name, $opts)) {
    $parser->_invoke(text => $block, out => \$value);
    $parser->{Hub}->{"/sys/response/head/blocks/js/<next>"} = $value;
  }
  $parser->get_ctx->{'collapse'} = 1;
  '';
}

# :js:global
#   ...
# :end js:global
sub _js_global {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my $value = '';
  if (my $block = _my_slurp($parser, $name, $opts)) {
    $parser->_invoke(text => $block, out => \$value);
    my $content = $parser->{Hub}->{"/sys/response/head/js"} || '';
    $parser->{Hub}->{"/sys/response/head/js"} = $content
      ? "$content\n$value"
      : $value;
  }
  $parser->get_ctx->{'collapse'} = 1;
  '';
}

# :js
#   ...
# :end js
#
# :js -global
#   ...
# :end js
#
# :js src='/res/js/livesite.js'
#
# :js event='window,load'
#   ...
# :end js
#
# :js extend='local'
#   ...
# :end js
sub _js {
  my $parser = shift;
  my $name = shift;
  my $opts = my_opts(\@_);
  my %args = @_;
  my $result = '';
  if (my $src = delete $args{'src'}) {
    $result = _js_src($parser, $name, $src, %args, -opts => $opts);
  } elsif (my $event = delete $args{'event'}) {
    $result = _js_event($parser, $name, $event, %args, -opts => $opts);
  } elsif (my $extend = delete $args{'extend'}) {
    $result = _js_extend($parser, $name, $extend, %args, -opts => $opts);
  } elsif ($$opts{'global'}) {
    $result = _js_global($parser, $name, %args, -opts => $opts);
  } else {
    $result = _js_closure($parser, $name, %args, -opts => $opts);
  }
  $result;
}

sub _my_slurp {
  my $parser = shift;
  my $name = shift;
  my $opts = shift; # note passed by ref
  my $block = $parser->_slurp($name);
  # Unique id (supresses multiple inclusion) of block content
  my $uid = undef;
  if ($uid = $$opts{'uid'}) {
    # -uid trumps -once
  } elsif (my $once = $$opts{'once'}) {
    $uid = join(':',
      $parser->get_ctx->{'path'},
      $parser->get_ctx->{'name'},
      $parser->get_ctx->{'elem'}{'B'},
    );
  }
  if ($uid) {
    $$parser{'Hub'}{'/sys/log'}->debug("Unique block uid=$uid");
    return '' if $$parser{'included'}{$uid};
    $$parser{'included'}{$uid} = 1;
  }
  $block;
}

sub _quote {
  my $value = shift;
  $value =~ s/(?<!\\)"/\\"/g;
  '"' . $value . '"';
}

1;

package Parse::Template::Directives::FileInfo;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Data::Hub::Util qw(:all);
use Time::Piece;

our %Directives;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  bless {%Directives}, $class;
}

sub _getvnode {
  my $parser = shift;
  my $name = shift;
  my $addr = shift;
  my $opts = my_opts(\@_);
  foreach my $k (keys %$opts) {
    my $v = $opts->{$k};
    $opts->{$k} = $parser->get_value_str(\$v);
  }
  $parser->get_ctx->{collapse} = 0;
  my $node = $parser->get_value(\$addr) or return;
  isa($node, FS('Node')) ? ($node, $opts) : undef;
};

sub _format_timestamp {
  my $seconds = shift;
  my $opts = shift;
  return $seconds unless $seconds;
  return $seconds unless $$opts{'strftime'};
  my $t = Time::Piece->new($seconds);
  $t->strftime($$opts{'strftime'});
}

sub _format_bytesize {
  my $bytes = shift;
  my $opts = shift;
  return $bytes unless $bytes;
  return $bytes unless $$opts{'quantize'};
  bytesize($bytes, -opts => $opts);
}

$Directives{'path'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_path;
};

$Directives{'addr'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_addr;
};

$Directives{'dev'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->dev;
};

$Directives{'ino'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->ino;
};

$Directives{'mode'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->mode;
};

$Directives{'nlink'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->nlink;
};

$Directives{'uid'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->uid;
};

$Directives{'gid'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->gid;
};

$Directives{'rdev'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_stat->rdev;
};

$Directives{'size'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  _format_bytesize($node->get_stat->size, $opts);
};

$Directives{'atime'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  _format_timestamp($node->get_stat->atime, $opts);
};

$Directives{'mtime'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  _format_timestamp($node->get_stat->mtime, $opts);
};

$Directives{'ctime'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  _format_timestamp($node->get_stat->ctime, $opts);
};

$Directives{'blksize'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  _format_bytesize($node->get_stat->blksize, $opts);
};

$Directives{'blocks'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  _format_bytesize($node->get_stat->blocks, $opts);
};

$Directives{'content'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_content;
};

$Directives{'type'}[0] = sub {
  my ($node, $opts) = _getvnode(@_) or return;
  $node->get_type;
};

1;

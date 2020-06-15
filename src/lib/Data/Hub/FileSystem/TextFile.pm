package Data::Hub::FileSystem::TextFile;
use strict;
our $VERSION = 0;

use Perl::Module;
use Data::Hub::Util qw(:all);
use Parse::Padding qw(padding);
use base qw(Data::Hub::FileSystem::File);
use Data::Format::Hash qw(:all);
use Data::Comparison qw();

sub __read_from_disk {
  my $tied = shift;
  delete $tied->__private->{orig};
  $tied->__content(file_read($tied->__path));
}

sub __write_to_disk {
  my $tied = shift;
  my $txt = $tied->__content || str_ref();
  my $data = $tied->__data;
  if (isa($data, 'HASH') && %$data) {
    my $diff = Data::Comparison::diff($tied->__private->{orig}, $tied->__data);
    my $disk_text = str_ref();
    # BEGIN CRITICAL SECTION
    my $h = fs_handle($tied->__path, 'w') or die $!; # LOCK
    binmode $h, ':utf8';
    if (-e $tied->__path) {
      local $/ = undef; # slurp
      $$disk_text = <$h>;
      my $data = Data::OrderedHash->new();
      $tied->___divide($disk_text, $data);
      Data::Comparison::merge(curry($data), $diff);
    }
    my $file_text = $$txt;
    if (length($file_text) > 0) {
      chomp $file_text;
      $file_text .= "\n";
    }
    $file_text .= "__DATA__\n" . hf_format($data);
    chomp $file_text; $file_text .= "\n"; # ensure nl at eof
    utf8::decode($file_text);
    seek $h, 0, 0;
    truncate $h, 0;
    print $h $file_text;
    close $h;
    # END CRTIICAL SECTION
    chomp $file_text;
    $tied->__raw_content(str_ref($file_text)); # copy
  } else {
    file_write($tied->__path, $txt);
  }
  $tied->__private->{orig} = clone($tied->__data, -keep_order);
}

sub __content {
  my $tied = shift;
  if (exists $_[0]) {
    # set
    my $c = isa($_[0], 'SCALAR') ? $_[0] : \$_[0];
    confess ('Undefined file content: ' . $tied->__path) unless defined($$c);
#warn sprintf("__content (%s): %d\n", $tied->__path, length($$c));
    $tied->__raw_content(str_ref($$c)); # copy
    my $data = $tied->__data;
    %$data = ();
    $tied->___divide($c, $data);
    $tied->__private->{orig} ||= clone($data, -keep_order);
    $tied->___content($c);
  } else {
    # get
    $tied->___content;
  }
}

sub ___divide {
  my $tied = shift or return;
  my $c = shift or return;
  my $data = shift or return;
  my $data_pos = index $$c, '__DATA__';
  if ($data_pos >= $[) {
    my @padding = padding($c, $data_pos, $data_pos + length('__DATA__'), -crlf);
    if (($padding[0] > 0 || $data_pos == 0) && $padding[1] > 0) {
      my $beg = $data_pos;
      my $width = length($$c) - $beg;
      my $data_str = substr $$c, $beg, $width, '';
      my $trim = length('__DATA__') + $padding[1];
      $data_str = substr $data_str, $trim;
      chomp $data_str;
      $tied->___deserialize_data(\$data_str, $data);
    }
  }
  $data;
}

sub ___deserialize_data {
  my $tied = shift or return;
  my $serialized_ref = shift or return;
  my $data_ref = shift or return;
  my ($format) = $$serialized_ref =~ /^#!\s*(csv|hf|json|yaml)/;
  if ($format) {
    warn "Deserialize from $format\n";
  }
  hf_parse($serialized_ref, -into => $data_ref, -hint => $tied->__path);
  $data_ref;
}

sub __serialize_data {
}

1;

__END__

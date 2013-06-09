package Data::Hub::FileSystem::HashFile;
use strict;
use Perl::Module;
use Encode;
use Data::Hub::Util qw(:all);
use Data::Format::Hash qw(:all);
use Data::Compare qw();
use Data::OrderedHash;
use base qw(Data::Hub::FileSystem::TextFile);
use Try::Tiny;

# ------------------------------------------------------------------------------
# Encoding
#
#   ON DISK       SERIALIZED
#
#   \xc4\x80      \x{100}
#
# Remember 
#
#   utf8::encode($string);  # "\x{100}"  becomes "\xc4\x80"
#   utf8::decode($string);  # "\xc4\x80" becomes "\x{100}"
#
# Of course that should be written:
#
#   $string = Encode::encode('utf8', $string);
#   $string = Encode::decode('utf8', $string);
#
# Perl strings are made up of `characters` like:
#
#   \x{100}
#
# Also:
#
#   http://perlgeek.de/en/article/encodings-and-unicode
#
# ------------------------------------------------------------------------------

# Object

sub sort_by_key {
  my $self = shift;
  my $data = $self->get_data;
  return unless $data->can('sort_by_key');
  $data->sort_by_key(@_);
  undef;
}

sub rename_entry {
  my $self = shift;
  my $data = $self->get_data;
  if ($data->can('rename_entry')) {
    return $data->rename_entry(@_);
  } else {
    return $data->{$_[0]} = delete $$data{$_[1]};
  }
}

# Tied object

sub __rw_utf8 {
  1;
}

sub __parse {
  my $tied = shift;
  return hf_parse($_[0], -into => $_[1], -hint => $tied->__addr);
}

sub __format {
  my $tied = shift;
  return hf_format($_[0], -as_ref, -with_crown);
}

sub __content {
  my $tied = shift;
  my $c = exists $_[0] ? str_ref($_[0]) : undef;
  if (defined $c) {
    $tied->__raw_content($c);
    my $private = $tied->__private;
    if (!exists($$private{txt}) || $tied->__has_crown($c)) {
      # When reading from disk, the txt semiphore will not exist and we will
      # always attempt to parse the content.  It is only when an instance which
      # has already been read from disk and has been told to set its content
      # that we need to do the text-downgrade song-and-dance.
      my $data = $tied->__data;
      %$data = ();
      try {
        $tied->__parse($c, $data);
        $tied->__private->{txt} = 0;
        $tied->__private->{orig} ||= clone($data, -keep_order); # set on initial read
      } catch {
        warn sprintf("Parse error: file='%s'; error='%s'", $tied->__path, $_);
        $tied->__private->{txt} = 1; # treat as text file
      };
    } else {
      # Has changed type to a text file
      $tied->__private->{txt} = 1;
    }
    return $tied->___content($c);
  } else {
    return $tied->___content;
  }
}

sub __read_from_disk {
  my $tied = shift;
  delete $tied->__private->{txt};
  delete $tied->__private->{orig};
  $tied->__content(
    $tied->__rw_utf8()
      ? file_read($tied->__path)
      : file_read_binary($tied->__path)
  );
}

sub __write_to_disk {
  my $tied = shift;
  if ($tied->__private->{txt}) {
    return $tied->SUPER::__write_to_disk;
  }
  my $diff = Data::Compare::diff($tied->__private->{orig}, $tied->__data);
#warn sprintf("DIFF: %s\n%s", $tied->__path, $diff->to_string);
  if (-e $tied->__path) {
    # BEGIN CRITICAL SECTION
    my $h = fs_handle($tied->__path, 'rw') or die $!; # LOCK
    binmode $h, ':encoding(UTF-8)' if $tied->__rw_utf8();
    my $c = str_ref();
    {
      local $/ = undef; # slurp
      $$c = <$h>;
    }
    my $data = Data::OrderedHash->new();
    $tied->__parse($c, $data);
    # XXX: Possible unicode mismatch between $data and $diff
    Data::Compare::merge(curry($data), $diff);
    $c = $tied->__format($data);
##  chomp $$c; $$c .= "\n"; # ensure nl at eof
    # The $h has the UTF-8 layer (meaning encode on write)
    # There should be no reason to do this
    # $$c = Encode::decode('UTF-8', $$c) if $tied->__rw_utf8() && !Encode::is_utf8($$c);
    seek $h, 0, 0;
    truncate $h, 0;
    print $h $$c;
    close $h;
    # END CRITICAL SECTION
##  chomp $$c;
    $tied->__raw_content($c);
    $tied->___content($c);
  } else {
    my $c = $tied->__format($tied->__data);
    $tied->___content($c);
##  chomp $$c; $$c .= "\n"; # ensure nl at eof
    if ($tied->__rw_utf8()) {
      file_write($tied->__path, $c);
    } else {
      file_write_binary($tied->__path, $c);
    }
  }
  $tied->__private->{orig} = clone($tied->__data, -keep_order);
}

sub __has_crown {
  my $tied = shift;
  my $c = shift or return;
  my $s = str_ref($c);
  $$s =~ /#\s?HashFile/;
}

1;

__END__

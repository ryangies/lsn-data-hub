package Data::Format::Nml::Document;
use strict;
use Data::Format::Nml::Node;

# $PAT_HEAD - Heading
our $PAT_HEAD = qr/^([\=\-\~]){4,}$/;

# $PAT_ITEM - List Item
our $PAT_ITEM = qr/^(\s*)((?:\*|\d{1,3}[\.\)]{1,2})\s+)/;

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {}, $class;
  $self->parse(@_);
  $self;
}

sub init {
  my $self = shift;
  my $root = Data::Format::Nml::Node->new();
  %$self = (
    text => shift,
    buffer => '',
    root => $root,
    node => $root,
  );
}

sub parse {
  my $self = shift;
  my $text = shift or return;
  $self->init($text);
  for (split $/, $self->{text}) {
    s/\s+$//;
    if (/$PAT_HEAD/) {
      # Heading
      my $char = substr $1, 0, 1;
      my $level = $char eq '=' ? 2 : $char eq '-' ? 3 : $char eq '~' ? 4 : 5;
      $self->commit("h$level");
    } elsif (/$PAT_ITEM/) {
      # List item
      $self->commit;
      $self->append($_);
    } elsif (!$_) {
      # Empty line
      $self->commit;
    } else {
      $self->append($_);
    }
  }
  $self->commit;
}

sub append {
  my $self = shift;
  my $buf = shift;
  $self->{buffer} .= "$buf\n";
}

sub commit {
  my $self = shift;
  my $buf = $self->{buffer} or return;
  my $tag = shift;
  $self->{node} = $self->{node}->append($tag, $buf);
  $self->{buffer} = '';
}

sub to_string {
  my $self = shift;
  return '' unless $self->{root};
  $self->{root}->to_string;
}

sub get_toc {
  my $self = shift;
  return unless $self->{root};
  my $toc = [];
  my $a = $self->{root}{childNodes};
  for (@$a) {
    $_->{tagName} =~ /^h(\d)$/ and  push @$toc, {
      level => $1,
      name => $_->{textContent},
    };
  }
  $toc;
}

1;

__END__

=pod:summary No mark-up language

=pod:synopsis

  use Data::Format::Nml::Document;
  my $doc = Data::Format::Nml::Document->new($txt);
  print $doc->to_string;

If C<$txt> is:

  My::Module v1
  =============

  INSTALLATION
  ------------

  To install this module type the following:

    perl Makefile.PL
    make
    make test
    make install

  DEPENDENCIES
  ------------

    * Perl 5.8.0
    * Scalar::Util

than the above will print:

  <a name="My::Module v1
  "></a><h1>My::Module v1
  </h1><a name="INSTALLATION
  "></a><h2>INSTALLATION
  </h2>To install this module type the following:
  <pre><blockquote>perl Makefile.PL
  make
  make test
  make install
  </blockquote></pre><a name="DEPENDENCIES
  "></a><h2>DEPENDENCIES
  </h2><ul><li>Perl 5.8.0
  </li><li>Scalar::Util
  </li></ul>

=pod:description

Format ordinary text as HTML.  Ordinary meaning there are no mark-up specific
tags.  The challenge is mostly keeping track of the indentation level of ordered
and unordered lists.

=cut

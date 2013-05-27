package Data::Format::Nml::Node;
use strict;

# Inline characters which indicate HTML tags
our %Char_To_Tag_Map = (
  '\*' => 'b',
  '\_' => 'u',
  '\`' => 'tt',
  '\^' => 'sup',
);

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $tag = shift;
  my $txt = shift;
  my $self = bless {
    tagName => $tag || '',
    parentNode => undef,
    textContent => $txt,
    childNodes => [],
    indent => 0,
    margin => 0,
  }, $class;
  $self->parse;
  $self;
}

sub parse {
  my $self = shift;
  return unless defined($self->{textContent});
  my $text = \$self->{textContent} or return;
  my $tag = '#text';
  if ($$text =~ s/$Data::Format::Nml::Document::PAT_ITEM//) {
    $self->{indent} = length($1);
    $self->{margin} = length($1.$2);
    $self->{parentType} = $2 =~ /^\*/ ? 'ul' : 'ol';
    $tag = 'li';
  } elsif ($$text =~ /^(\s{2,})/) {
    $self->{indent} = length($1);
  } elsif ($$text =~ /^(\>|&gt;)/) {
    $$text =~ s/^(\>|&gt;)\s*//;
    $$text =~ s/^(\>|&gt;)\s*/<br\/>/gm;
    $self->{indent} = length($1);
    $tag = 'blockquote';
  }
  $self->{tagName} ||= $tag;
}

sub markup_inline {
  my $buf = $_[0] or return $_[0];
  foreach my $char (keys %Char_To_Tag_Map) {
    my $tag = $Char_To_Tag_Map{$char};
    $buf =~ s/(^|\s)$char(.*?)$char(\W|$)/$1<$tag>$2<\/$tag>$3/g;
  }
  # Format numbers 1st, 2nd, 3rd, 4th, ...
  $buf =~ s/\b(\d+)(st|nd|rd|th)\b/$1<sup>$2<\/sup>/g;
  $buf;
}

sub append {
  my $self = shift;
  my $node = Data::Format::Nml::Node->new(@_);
  my $can_format = 1;

  if ($node->{indent} > $self->{indent} && $node->{tagName} eq '#text') {
    $node->{tagName} = 'pre';
    my $i = $node->{indent};
    $i <= 4 and $node->{textContent} =~ s/^\s{$i}//gm;
    $can_format = 0;
  } elsif ($node->{tagName} =~ /^h\d$/) {
    while ($self->{parentNode}) {
      $self = $self->{parentNode};
    }
  } else {
    while ($node->{indent} < $self->{indent} && $self->{parentNode}) {
      $self = $self->{parentNode};
      $self->{tagName} eq 'li' and $self = $self->{parentNode};
    }
  }

  $node->{textContent} = markup_inline($node->{textContent}) if $can_format;

  if ($self->{tagName} eq '#text' && $node->{tagName} eq '#text') {
    $self->{textContent} .= $node->{textContent};
    return $self;
  }

  if ($node->{tagName} eq 'li') {
    if ($self->{tagName} ne $node->{parentType} ||
      $self->{indent} < $node->{indent}) {
      my $pnode = Data::Format::Nml::Node->new($node->{parentType});
      $pnode->{indent} = $node->{indent};
      $pnode->{margin} = $node->{margin};
      $pnode->appendChild($node);
      $node = $pnode;
    }
  }
  
  if ($self->{tagName} =~ /^[ou]l$/ && $node->{tagName} ne 'li') {
    my $cn = $self->{childNodes};
    my $tail = $cn->[@$cn -1];
    $tail->appendChild($node);
  } else {
    $self->appendChild($node);
  }

  if ($node->{tagName} =~ /^[ou]l$/) {
    return $node;
  }

  $self;
}

sub appendChild {
  my $self = shift;
  my $node = shift;
  $node->{parentNode} = $self;
  push @{$self->{childNodes}}, $node;
}

sub to_string {
  my $self = shift;
  my $tag = $self->{tagName};
  my $txt = $self->{textContent};
  $tag and $tag eq '#text' and return "<p>$txt</p>";
  my $result = '';
  if ($tag) {
    if ($tag =~ /^h\d$/) {
      chomp $txt;
      $result .= "<$tag id=\"$txt\">";
    } elsif ($tag eq 'pre') {
      $result .= '<blockquote><pre>';
    } else {
      $result .= "<$tag>";
    }
  }
  $result .= $txt if $txt;
  for (@{$self->{childNodes}}) {
    $result .= $_->to_string;
  }
  if ($tag) {
    if($tag eq 'pre') {
      $result .= '</pre></blockquote>';
    } else {
      $result .= "</$tag>";
    }
  }
  $result;
}

1;

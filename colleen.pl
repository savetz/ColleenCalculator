use strict;

sub write_file {
  my ($file, $out) = @_;

  my $fh;
  open $fh, '>', $file or die;
  binmode $fh;
  print $fh $out;
  close $fh;
}

sub open_lst {
  my ($file) = @_;
  open my $fh, '<', $file or die;
  $fh;
}


sub symbols {
  my ($fh, $line, $data) = @_;

  my $last = '';
  while (<$fh>) {
    $line++;
    chomp;

    next if $_ eq '';
    next if /^\x0c?COLLEEN/;  # skip form feed and title line
    if (/^(\w.{6} [0-9A-F]{4}    ){0,3}(\w.{6} [0-9A-F]{4} )$/) {
      my (@vals) = split /\s+/, $_;
      for (my $i = 0; $i < scalar(@vals); $i += 2) {
        my $sym = $vals[$i];
        my $addr = $vals[$i + 1];
        my $cmp = $last cmp $sym;
        $last = $sym;
        print STDERR "SYM: $sym\n" if $cmp != -1;
        my $expected = $data->{$sym};
        print STDERR "ADDR: $sym: $addr != $expected\n" if $expected ne $addr;
      }
    }
    else {
      print STDERR "$line: $_\n";
    }
  }
}

sub strip {
  my $fh = open_lst(@_);

  while (<$fh>) {
    chomp;
    last if /^\s+SYMBOL TABLE $/;
    next if /^\x0c?COLLEEN/;  # skip form feed and title line
    my ($output, $rest) = (/^(.{0,20})(.*)/);
    print "$rest\n";
  }
}

sub lst2mads {
  my ($line, $next, $out, $offset) = (0, -1, "\xff\xff\0\0\0\0", 2);

  my $data = {};
  my $fh = open_lst(@_);
  while (<$fh>) {
    $line++;
    chomp;

    next if /^\x0c?COLLEEN/;  # skip form feed and title line
    print STDERR "CHAR: $line: $_\n" if /[^\x20-\x40A-Z\[\\\]\^_|]/; # detect odd characters
    print STDERR "SPAC: $line: $_\n" if /\s+ $/;

    symbols($fh, $line, $data) if /^\s+SYMBOL TABLE $/;

    my ($output, $rest) = (/^(.{0,20})(.*)/);

    # Validate output prefix
    my ($addr, $vals, $count) = (undef, '', 0);

    if ($output =~ /^([0-9A-F]{4})((?: [0-9A-F][0-9A-F])*)\s*$/) {
      ($addr, $vals) = ($1, $2);
    }
    elsif ($output =~ /^([0-9A-F]{4})\s+$/) {
    }
    elsif ($output =~ /^\s+$/ || $output eq '') {
    }
    else {
      die "$line: OUTPUT: $output\n";
    }

    if (defined $addr) {
      $addr = hex $addr;
      $vals =~ s/ //g;
      my @vals = unpack "C*", pack "H*", $vals;
      $count = scalar(@vals);
      if ($addr != $next) {
        printf STDERR "%4d: ADDR: $_\n", $line if $count > 0;
        my $len = length($out) - $offset - 4;
        if ($len > 0) {
          printf STDERR "%4d: OFFS: %04lx:%04lx -> %04lx\n", $line, $offset, $next - $len, $next - 1;
          substr($out, $offset, 4) = pack "vv", $next - $len, $next - 1;
          $offset = length($out);
          $out .= "\0\0\0\0";
        }
      }

      $out .= chr $_ for @vals;
      $next = $addr + $count;
    }

    $rest =~ s/\s*(?<!');.*//;  # truncate comments
    $rest =~ s/^(.{22}  )\S.*$/\1/; # truncate comments
    $rest =~ s/^(.{29}   )\S.*$/\1/; # truncate comments
    $rest =~ s/ CENTRAL INPUT OUTPUT ROUTINE $//;
    $rest =~ s/ SUCCESSFUL OPERATION $//;
    $rest =~ s/ STACK LABELS $//;
    $rest =~ s/(\*=\*(\+\d)?)\s+\S.*$/\1/;  # truncate comments
    $rest =~ s/\s+$//; # truncate trailing whitespace

    if ($rest =~ /^(\w{1,6}\??)/ && defined $addr) {
        $data->{$1} = sprintf "%04lX", $addr;
    }

    if ($rest =~ /^$/) {
    }
    elsif ($rest =~ /^(\s+)\.(PAGE|TITLE)/ && length($1) == 8) {
    }
    elsif ($rest =~ /^(\w+\s*)=\s+\S+/ && length($1) == 8) {
    }
    elsif ($rest =~ /^(\w*\??\s+)\*=\s*\S+/ && length($1) <= 8) {
    }
    elsif ($rest =~ /^(\w+)$/ && length($1) <= 8 && $count == 0) {
    }
    elsif ($rest =~ /^(\s+)(\.IF|\.ENDIF|\.END)/ && length($1) == 8) {
    }
    elsif ($rest =~ /^(\w*\s+)(\.(?:BYTE|WORD)\s+)/ && length($1) == 8 && length($2) >= 8) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(ASL|LSR|RO[LR])     A$/ && length($1) == 8 && $count == 1) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(TX[AS]|TA[XY]|TSX|TYA|IN[XY]|DE[XY])$/ && length($1) == 8 && ($count == 1 || $count == 0)) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(BRK|CL[CDIV]|SE[CDI]|RT[IS]|P[HL][AP]|NOP)$/ && length($1) == 8 && ($count == 1 || $count == 0)) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(JSR|JMP)     \S+$/ && length($1) == 8 && ($count == 3 || $count == 0)) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(LD[AXY]|CMP|CP[XY]|ADC|SBC|AND|EOR|ORA)     (\S+$|#)/ && length($1) == 8 && ($count == 2 || $count == 0)) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(?:LD[AXY]|ST[AXY]|BIT|CMP|CP[XY])     \S+$/ && length($1) == 8 && ($count == 2 || $count == 3 || $count == 0)) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(ADC|SBC|INC|DEC|ASL|LSR|RO[LR]|AND|EOR|ORA)     \S+$/ && length($1) == 8 && ($count == 2 || $count == 3 || $count == 0)) {
    }
    elsif ($rest =~ /^(:?\w*\s+)(BNE|BEQ|BC[CS]|BMI|BPL|BV[CS])     \S+$/ && length($1) == 8 && ($count == 2 || $count == 0)) {
    }
    else {
      die "$line: REST: $rest, $count";
    }

    # transform *=CONST+* to *=*+CONT
    $rest =~ s/\*=(\S+\*FPREC)\+\*/\*=\*\+\1/;

    # Convert to MADS usage.
    $rest =~ s/^(\s*\.(?:PAGE|TITLE|END)\b)/;\1/;
    $rest =~ s/\b([A-Z0-9]+)\s+\*=\s*\*\s*\+/\1 .DS /;
    $rest =~ s/^(\w*\??\s+)\*=/\1ORG /;
    $rest =~ s/(\s+(?:ASL|LSR|ROR|ROL)\s+)A(\s+|$)/\1\2/;
    if ($rest =~ /\.BYTE/) {
      $rest =~ s/'(.)([\-\+])/"\1"\2/g;
      $rest =~ s/'/''/;
      $rest =~ s/"/'/g;
    }

    # Massage immediate comments.
    $rest =~ s/\#([A-Z][A-Z0-9]+)$/\#\1&\$FF/;
    $rest =~ s/\#([A-Z].*)\/256$/#(\1)\/256/;
    $rest =~ s/\#([A-Z].*)$/#(\1)&\$FF/;
    $rest =~ s/\#(\d\*.*)/#(\1)&\$FF/;

    # Handle incomplete single quotes
    $rest =~ s/#'(.)([\-\+])/#'\1'\2/;
    $rest =~ s/#'$/#' '/;
    $rest =~ s/#'(.)$/#'\1'/;
    $rest =~ s/\-\'(.)/-'\1'/;

    # Edit the code to compile
    $rest =~ s/FPSLEN-1\*FPREC/(FPSLEN-1)*FPREC/;
    $rest =~ s/ORG \*\-1\/256\+1\*256/ORG ((*-1)\/256+1)*256/;
    $rest =~ s/,(KBUFF|PBUFF|TOKBUF),/,\1&\$FF,/;
    $rest =~ s/SCLSTAT/SCLSTA/;
    $rest =~ s/SNOTRACE/SNOTRA/;

    print "$rest\n";
  }

  my $len = length($out) - $offset - 4;
  printf STDERR "%4d: OFFS: %04lx:%04lx -> %04lx\n", $line, $offset, $next - $len, $next - 1;
  substr($out, $offset, 4) = $len > 0 ? pack "vv", $next - $len, $next - 1 : '';

  write_file('check.obx', $out);
}

sub main {
  my $opt = shift;
  if ($opt eq '-mads') {
    lst2mads(@_);
  }
  elsif ($opt eq '-strip') {
    strip(@_);
  }
}

main(@ARGV);

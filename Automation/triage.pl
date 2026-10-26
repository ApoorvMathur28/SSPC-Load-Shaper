#!/usr/bin/perl
use strict;
use warnings;

#======================================================================
# triage.pl - parse an xsim log of the SSPC verification run and print
# a summary: scoreboard pass/fail, baseline brown-outs, coverage, and
# the list of failing scenarios. Exits 1 if any check failed (CI gate).
# Handles Windows PowerShell logs (UTF-16 + BOM) and CRLF line endings.
#   usage: perl triage.pl sim_output.log
#======================================================================

my $logfile = $ARGV[0] // "sim_output.log";

open(my $fh, "<:raw", $logfile) or die "Cannot open $logfile: $!\n";
my $data = do { local $/; <$fh> };
close($fh);

$data =~ s/^\xFF\xFE//;        # UTF-16 LE BOM
$data =~ s/^\xFE\xFF//;        # UTF-16 BE BOM
$data =~ s/^\xEF\xBB\xBF//;    # UTF-8 BOM
$data =~ s/\x00//g;            # null bytes left by UTF-16

my ($passes, $fails, $coverage) = (0, 0, "N/A");
my ($base_bo, $base_runs) = ("N/A", "N/A");
my $seen_score = 0;
my @failing;

foreach my $line (split /\r?\n/, $data) {
    if ($line =~ /SCOREBOARD:\s+(\d+)\s+passed,\s+(\d+)\s+failed/) {
        ($passes, $fails) = ($1, $2); $seen_score = 1;
    }
    if ($line =~ /BASELINE:\s+(\d+)\s+of\s+(\d+)/) {
        ($base_bo, $base_runs) = ($1, $2);
    }
    if ($line =~ /COVERAGE:\s+([\d.]+)%/) {
        $coverage = $1;
    }
    if ($line =~ /^\[FAIL\]\s+(.*)/) {
        push @failing, $1;
    }
}

print "=" x 60, "\n";
print " SSPC Verification - Triage Report ($logfile)\n";
print "=" x 60, "\n";
printf " Shaped turn-ons passed : %d\n", $passes;
printf " Shaped turn-ons failed : %d\n", $fails;
printf " Baseline brown-outs    : %s of %s unprotected runs\n", $base_bo, $base_runs;
printf " Functional coverage    : %s%%\n", $coverage;
if (!$seen_score) {
    print "\n WARNING: no scoreboard summary found - did the run reach \$finish?\n";
} elsif (@failing) {
    print "\n Failing scenarios:\n";
    print "   - $_\n" for @failing;
} else {
    print "\n All shaped turn-ons met the spec.\n";
}
print "=" x 60, "\n";
exit(($fails > 0 || !$seen_score) ? 1 : 0);

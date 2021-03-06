use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $TEST_SQL = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($TEST_SQL->connector, $FILE_CONFIG);
my $RVD_FRONT= rvd_front($TEST_SQL->connector, $FILE_CONFIG);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $TEST_SQL->connector);

my @VMS = ('KVM');
my $USER = create_user("foo","bar");

#############################################################################

sub test_create_domain {
    my ($vm_name, $vm) = @_;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , arg_create_dom($vm_name))
    };

    ok($domain,"Domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    return $domain;
}

sub test_wrong_args {
    my ($vm_name, $vm) = @_;

    eval { $RVD_BACK->import_domain( vm => 'nonvm', user => $USER->name, name => 'a') };
    like($@,qr/unknown VM/i);

    eval { $RVD_BACK->import_domain( vm => $vm_name,user => 'nobody', name => 'a') };
    like($@,qr/unknown user/i);

}

sub test_already_there {
    my ($vm_name, $vm) = @_;


    my $domain = test_create_domain($vm_name, $vm);
    ok($domain,"Create domain") or return;
    eval {
        my $domain_imported = $RVD_BACK->import_domain(
                                        vm => $vm_name
                                     ,name => $domain->name
                                     ,user => $USER->name
        );
    };
    like($@,qr/already in RVD/i,"Test import fail, expecting error");

    return $domain;
}

sub test_import {
    my ($vm_name, $vm, $domain) = @_;

    my $dom_name = $domain->name;

    my $sth = $TEST_SQL->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth->execute($domain->id);
    $domain = undef;

    $domain = $RVD_BACK->search_domain( vm => $vm, name => $dom_name );
    ok(!$domain,"Expecting domain $dom_name removed") or return;

    eval {
        $domain = $RVD_BACK->import_domain(
                                        vm => $vm_name
                                     ,name => $dom_name
                                     ,user => $USER->name
        );
    };
    diag($@) if $@;
    ok($domain,"Importing domain $dom_name");

    my $domain2 = $RVD_BACK->search_domain($dom_name);
    ok($domain2, "Search domain in Ravada");
}

sub test_import_spinoff {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm('kvm');
    my $domain = test_create_domain($vm_name,$vm);
    $domain->is_public(1);
    my $clone = $domain->clone(name => new_domain_name(), user => $USER);
    ok($clone);
    ok($domain->is_base,"Expecting base") or return;

    $clone->remove($USER);

    for my $volume ( $domain->list_disks ) {
        my $info = `qemu-img info $volume`;
        my ($backing) = $info =~ m{(backing file.*)};
        ok($backing,"Expecting volume with backing file") or return;
    }

    my $dom_name = $domain->name;

    my $sth = $TEST_SQL->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth->execute($domain->id);
    $domain = undef;

    $domain = $RVD_BACK->search_domain( vm => $vm, name => $dom_name );
    ok(!$domain,"Expecting domain $dom_name removed") or return;

    eval {
        $domain = $RVD_BACK->import_domain(
                                        vm => $vm_name
                                     ,name => $dom_name
                                     ,user => $USER->name
        );
    };
    diag($@) if $@;
    ok($domain,"Importing domain $dom_name");

    my $domain2 = $RVD_BACK->search_domain($dom_name);
    ok($domain2, "Search domain in Ravada");

    for my $volume ( $domain2->list_disks ) {
        my $info = `qemu-img info $volume`;
        my ($backing) = $info =~ m{(backing file.*)};
        ok(!$backing,"Expecting volume without backing file");
    }


}

############################################################################

remove_old_domains();
remove_old_disks();

for my $vm_name (@VMS) {
    my $vm = $RVD_BACK->search_vm($vm_name);
    SKIP : {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED test: $vm_name must be tested from root user";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_wrong_args($vm_name, $vm);

        my $domain = test_already_there($vm_name, $vm);
        test_import($vm_name, $vm, $domain) if $domain;

        test_import_spinoff($vm_name);
    }
}

remove_old_domains();
remove_old_disks();

done_testing();


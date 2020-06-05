require 'spec_helper'
require 'net/ssh'

postgresql_host = '127.0.0.1'
postgresql_default_port = 5432
pgbouncer_default_port = 6432
elasticsearch_host = listInventoryHosts("logging")[0]
elasticsearch_api_port = 9200
replicated = readDataYaml("configuration/postgresql")["specification"]["replication"]["enable"]
replication_user = readDataYaml("configuration/postgresql")["specification"]["replication"]["user"]
replication_password = readDataYaml("configuration/postgresql")["specification"]["replication"]["password"]
max_wal_senders = readDataYaml("configuration/postgresql")["specification"]["replication"]["max_wal_senders"]
wal_keep_segments = readDataYaml("configuration/postgresql")["specification"]["replication"]["wal_keep_segments"]
pgbouncer_enabled = readDataYaml("configuration/postgresql")["specification"]["additional_components"]["pgbouncer"]["enabled"]
pgaudit_enabled = readDataYaml("configuration/postgresql")["specification"]["extensions"]["pgaudit"]["enabled"]
pg_user = 'testuser'
pg_pass = 'testpass'

def queryForCreating
  describe 'Checking if it is possible to create a test schema' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c \"psql -t -c 'CREATE SCHEMA serverspec_test;'\"") do
      its(:stdout) { should match /^CREATE SCHEMA$/ }
      its(:exit_status) { should eq 0 }
    end
  end

  describe 'Checking if it is possible to create a test table' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c \"psql -t -c 'CREATE TABLE serverspec_test.test (col varchar(20));'\"") do
      its(:stdout) { should match /^CREATE TABLE$/ }
      its(:exit_status) { should eq 0 }
    end
  end

  describe 'Checking if it is possible to insert values into the test table' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c \"psql -t -c \\\"INSERT INTO serverspec_test.test (col) values ('SUCCESS');\\\"\"") do
      its(:stdout) { should match /^INSERT 0 1$/ }
      its(:exit_status) { should eq 0 }
    end
  end
end

def queryForSelecting
  describe 'Checking if it is possible to select values from the test table' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c \"psql -t -c 'SELECT * from serverspec_test.test;'\"") do
      its(:stdout) { should match /\bSUCCESS\b/ }
      its(:exit_status) { should eq 0 }
    end
  end
end

def queryForAlteringTable
  describe 'Altering table with multiline command to verify multiline messages support' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c psql <<SQL
    ALTER TABLE serverspec_test.test
    ADD COLUMN id int,
    ADD COLUMN name text,
    ADD COLUMN city text,
    ADD COLUMN description text;
SQL") do
      its(:stdout) { should match /^ALTER TABLE$/ }
      its(:exit_status) { should eq 0 }
    end
  end
end

def queryForDropping
  describe 'Checking if it is possible to drop the test table' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c \"psql -t -c 'DROP TABLE serverspec_test.test;'\"") do
      its(:stdout) { should match /^DROP TABLE$/ }
      its(:exit_status) { should eq 0 }
    end
  end
  
  describe 'Checking if it is possible to drop the test schema' do
    let(:disable_sudo) { false }
    describe command("su - postgres -c \"psql -t -c 'DROP SCHEMA serverspec_test CASCADE;'\"") do
      its(:stdout) { should match /^DROP SCHEMA$/ }
      its(:exit_status) { should eq 0 }
    end
  end
end

# Running the 'systemctl is-active' command returns the result 'unknown'.
# https://bugzilla.redhat.com/show_bug.cgi?id=1073481
# Must first run the 'systemctl status' command to be able to view the service status withe the 'is-active' command.

describe 'Checking PostgreSQL service status' do
  describe command("systemctl status postgresql > /dev/null") do
    its(:exit_status) { should eq 0 }
  end
end

describe 'Checking if PostgreSQL service is running' do
  describe service('postgresql') do
    it { should be_enabled }
    it { should be_running }
  end
end

if os[:family] == 'redhat'
  describe 'Checking PostgreSQL directories and config files' do
    let(:disable_sudo) { false }
    describe file('/var/opt/rh/rh-postgresql10/lib/pgsql/data') do
      it { should exist }
      it { should be_a_directory }
    end
    describe file("/var/opt/rh/rh-postgresql10/lib/pgsql/data/pg_hba.conf") do
      it { should exist }
      it { should be_a_file }
      it { should be_readable }
     end
    describe file("/var/opt/rh/rh-postgresql10/lib/pgsql/data/postgresql.conf") do
      it { should exist }
      it { should be_a_file }
      it { should be_readable }
    end
  end
elsif os[:family] == 'ubuntu'
  describe 'Checking PostgreSQL directories and config files' do
    let(:disable_sudo) { false }
    describe file('/etc/postgresql/10/main') do
      it { should exist }
      it { should be_a_directory }
    end
    describe file("/etc/postgresql/10/main/pg_hba.conf") do
      it { should exist }
      it { should be_a_file }
      it { should be_readable }
     end
    describe file("/etc/postgresql/10/main/postgresql.conf") do
      it { should exist }
      it { should be_a_file }
      it { should be_readable }
    end
  end
end

describe 'Checking if the ports are open' do
  let(:disable_sudo) { false }
  describe port(postgresql_default_port) do
    it { should be_listening }
  end
end 

describe 'Checking if PostgreSQL is ready' do
  describe command("pg_isready") do
    its(:stdout) { should match /postgresql:#{postgresql_default_port} - accepting connections/ }
    its(:exit_status) { should eq 0 }
  end
end

describe 'Checking if it is possible to connect to PostgreSQL database' do
  let(:disable_sudo) { false }
  describe command("su - postgres -c \"psql -t -c 'SELECT 2+2;'\"") do
    its(:stdout) { should match /4/ }
    its(:exit_status) { should eq 0 }
  end
end

if !replicated
  queryForCreating
  queryForSelecting
  queryForAlteringTable
end   

if replicated

  primary = listInventoryHosts("postgresql")[0]
  secondary = listInventoryHosts("postgresql")[1]
 
  if primary.include? host_inventory['hostname']
    if os[:family] == 'redhat'
      describe 'Checking PostgreSQL config files for master node' do
        let(:disable_sudo) { false }
        describe command("cat /var/opt/rh/rh-postgresql10/lib/pgsql/data/postgresql.conf | grep wal_level") do
          its(:stdout) { should match /^wal_level = replica/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("cat /var/opt/rh/rh-postgresql10/lib/pgsql/data/postgresql.conf | grep max_wal_senders") do
          its(:stdout) { should match /^max_wal_senders = #{max_wal_senders}/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("cat /var/opt/rh/rh-postgresql10/lib/pgsql/data/postgresql.conf | grep wal_keep_segments") do
          its(:stdout) { should match /^wal_keep_segments = #{wal_keep_segments}/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("su - postgres -c \"psql -t -c '\\du'\" | grep #{replication_user}") do
          its(:stdout) { should match /#{replication_user}/ }
          its(:stdout) { should match /Replication/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("cat /var/opt/rh/rh-postgresql10/lib/pgsql/data/pg_hba.conf | grep replication | grep md5") do
          its(:stdout) { should match /#{replication_user}/ }
          its(:stdout) { should match /replication/ }
          its(:exit_status) { should eq 0 }
        end
      end
    elsif os[:family] == 'ubuntu'
      describe 'Checking PostgreSQL config files for master node' do
        let(:disable_sudo) { false }
        describe command("cat /etc/postgresql/10/main/postgresql.conf | grep wal_level") do
          its(:stdout) { should match /^wal_level = replica/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("cat /etc/postgresql/10/main/postgresql.conf | grep max_wal_senders") do
          its(:stdout) { should match /^max_wal_senders = #{max_wal_senders}/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("cat /etc/postgresql/10/main/postgresql.conf | grep wal_keep_segments") do
          its(:stdout) { should match /^wal_keep_segments = #{wal_keep_segments}/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("su - postgres -c \"psql -t -c '\\du'\" | grep #{replication_user}") do
          its(:stdout) { should match /#{replication_user}/ }
          its(:stdout) { should match /Replication/ }
          its(:exit_status) { should eq 0 }
        end
        describe command("cat /etc/postgresql/10/main/pg_hba.conf | grep replication | grep md5") do
          its(:stdout) { should match /#{replication_user}/ }
          its(:stdout) { should match /replication/ }
          its(:exit_status) { should eq 0 }
        end
      end
    end

    describe 'Checking the status of master node' do
      let(:disable_sudo) { false }
      describe command("su - postgres -c \"psql -t -c 'SELECT usename, state from pg_stat_replication;'\"") do
        its(:stdout) { should match /\bstreaming\b/ }
        its(:stdout) { should match /\b#{replication_user}\b/ }
        its(:exit_status) { should eq 0 }
      end
    end

    queryForCreating
    queryForSelecting
    queryForAlteringTable
    
  elsif secondary.include? host_inventory['hostname']
    if os[:family] == 'redhat'
      describe 'Checking PostgreSQL config files for secondary node' do
        let(:disable_sudo) { false }
        describe command("cat /var/opt/rh/rh-postgresql10/lib/pgsql/data/postgresql.conf | grep hot_standby") do
          its(:stdout) { should match /^hot_standby = on/ }
          its(:exit_status) { should eq 0 }
        end
        describe file('/var/lib/pgsql/.pgpass') do
          it { should exist }
          it { should be_readable }
          its(:content) { should match /#{replication_user}:#{replication_password}/ }
        end
      end
    elsif os[:family] == 'ubuntu'
      describe 'Checking PostgreSQL config files for secondary node' do
        let(:disable_sudo) { false }
        describe command("cat /etc/postgresql/10/main/postgresql.conf | grep hot_standby") do
          its(:stdout) { should match /^hot_standby = on/ }
          its(:exit_status) { should eq 0 }
        end
        describe file('/var/lib/postgresql/.pgpass') do
          it { should exist }
          it { should be_readable }
          its(:content) { should match /#{replication_user}:#{replication_password}/ }
        end
      end
    end

    describe 'Checking the state of replica nodes' do
      let(:disable_sudo) { false }
      describe command("su - postgres -c \"psql -t -c 'SELECT status, conninfo  from pg_stat_wal_receiver;'\"") do
        its(:stdout) { should match /\bstreaming\b/ }
        its(:stdout) { should match /\buser=#{replication_user}\b/ }
        its(:exit_status) { should eq 0 }
      end
    end

    queryForSelecting

  end
end

### Tests for PGBouncer

if pgbouncer_enabled

  if listInventoryHosts("postgresql")[0].include? host_inventory['hostname']

    describe 'Checking if PGBouncer service is running' do
      describe service('pgbouncer') do
        it { should be_enabled }
        it { should be_running }
      end
    end

    describe 'Creating a test user' do
      let(:disable_sudo) { false }
      describe command("su - postgres -c \"psql -t -c \\\"CREATE USER #{pg_user} WITH PASSWORD '#{pg_pass}';\\\"\" 2>&1") do
        its(:stdout) { should match /^CREATE ROLE$/ }
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Adding user to userlist.txt' do
      let(:disable_sudo) { false }
      describe command("echo \\\"#{pg_user}\\\" \\\"#{pg_pass}\\\" >> /etc/pgbouncer/userlist.txt && systemctl restart pgbouncer") do
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Granting privileges on schema to user' do
      let(:disable_sudo) { false }
      describe command("su - postgres -c \"psql -t -c 'GRANT ALL ON SCHEMA serverspec_test to #{pg_user}; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA serverspec_test to #{pg_user};'\" 2>&1") do
        its(:stdout) { should match /^GRANT$/ }
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Creating a test table' do
      let(:disable_sudo) { false }
      describe command("psql -h #{postgresql_host} -p #{pgbouncer_default_port} -U #{pg_user} postgres -c 'CREATE TABLE serverspec_test.pgbtest (col varchar(20));' 2>&1") do
        its(:stdout) { should match /^CREATE TABLE$/ }
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Inserting values into the test table' do
      let(:disable_sudo) { false }
      describe command("psql -h #{postgresql_host} -p #{pgbouncer_default_port} -U #{pg_user} postgres -c \"INSERT INTO serverspec_test.pgbtest (col) values ('PGBSUCCESS');\" 2>&1") do
        its(:stdout) { should match /^INSERT 0 1$/ }
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Selecting values from the test table' do
      let(:disable_sudo) { false }
      describe command("psql -h #{postgresql_host} -p #{pgbouncer_default_port} -U #{pg_user} postgres -c 'SELECT col from serverspec_test.pgbtest;' 2>&1") do
        its(:stdout) { should match /\bPGBSUCCESS\b/ }
        its(:exit_status) { should eq 0 }
      end
    end

  end

  if replicated || (listInventoryHosts("postgresql")[0].include? host_inventory['hostname'])

    describe 'Selecting values from test tables' do
      let(:disable_sudo) { false }
      describe command("PGPASSWORD=#{pg_pass} psql -h #{postgresql_host} -p #{postgresql_default_port} -U #{pg_user} postgres -c 'SELECT * from serverspec_test.test;' 2>&1") do
        its(:stdout) { should match /\bSUCCESS\b/ }
        its(:exit_status) { should eq 0 }
      end
      describe command("PGPASSWORD=#{pg_pass} psql -h #{postgresql_host} -p #{postgresql_default_port} -U #{pg_user} postgres -c 'SELECT col from serverspec_test.pgbtest;' 2>&1") do
        its(:stdout) { should match /\bPGBSUCCESS\b/ }
        its(:exit_status) { should eq 0 }
      end    
    end

  end

end

### Cleaning up

if !replicated
  queryForDropping
end

if replicated && (listInventoryHosts("postgresql")[1].include? host_inventory['hostname'])
  describe 'Cleaning up' do
    it "Delegating drop table query to master node" do
      Net::SSH.start(listInventoryIPs("postgresql")[0], ENV['user'], keys: [ENV['keypath']], :keys_only => TRUE) do|ssh|
        result = ssh.exec!("sudo su - postgres -c \"psql -t -c 'DROP TABLE serverspec_test.test;'\" 2>&1")
        expect(result).to match 'DROP TABLE'
      end
    end
    it "Delegating drop table query to master node", :if => pgbouncer_enabled  do
      Net::SSH.start(listInventoryIPs("postgresql")[0], ENV['user'], keys: [ENV['keypath']], :keys_only => TRUE) do|ssh|
        result = ssh.exec!("sudo su - postgres -c \"psql -t -c 'DROP TABLE serverspec_test.pgbtest;'\" 2>&1")
        expect(result).to match 'DROP TABLE'
      end
    end      
    it "Delegating drop schema query to master node" do
      Net::SSH.start(listInventoryIPs("postgresql")[0], ENV['user'], keys: [ENV['keypath']], :keys_only => TRUE) do|ssh|
        result = ssh.exec!("sudo su - postgres -c \"psql -t -c 'DROP SCHEMA serverspec_test;'\" 2>&1")
        expect(result).to match 'DROP SCHEMA'
      end
    end
    it "Delegating drop user query to master node", :if => pgbouncer_enabled do
      Net::SSH.start(listInventoryIPs("postgresql")[0], ENV['user'], keys: [ENV['keypath']], :keys_only => TRUE) do|ssh|
        result = ssh.exec!("sudo su - postgres -c \"psql -t -c 'DROP USER #{pg_user};'\" 2>&1")
        expect(result).to match 'DROP ROLE'
      end
    end
    it "Removing test user from userlist.txt", :if => pgbouncer_enabled do
      Net::SSH.start(listInventoryIPs("postgresql")[0], ENV['user'], keys: [ENV['keypath']], :keys_only => TRUE) do|ssh|
        result = ssh.exec!("sudo su - -c \"sed -i '/#{pg_pass}/d' /etc/pgbouncer/userlist.txt && cat /etc/pgbouncer/userlist.txt\" 2>&1")
        expect(result).not_to match "#{pg_pass}"
      end
    end    
  end
end

### Tests for PGAudit

if pgaudit_enabled

  if !replicated || (replicated && (listInventoryHosts("postgresql")[1].include? host_inventory['hostname']))

    describe 'Checking if the Elasticsearch logs contain queries from the PostrgeSQL database' do
      describe command("sleep 60 && curl -k -u admin:admin 'https://#{elasticsearch_host}:#{elasticsearch_api_port}/_search?pretty=true' -H 'Content-Type: application/json' -d '{\"size\":100,\"_source\":{\"includes\":\"message\"},\"query\":{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match_phrase\":{\"source\":\"/var/log/postgresql/postgresql-10-main.log\"}},{\"match_phrase\":{\"source\":\"/var/log/postgresql/postgresql.log\"}}],\"minimum_should_match\":1}}],\"filter\":{\"query_string\":{\"query\":\"*serverspec*\"}}}}}'") do
        its(:stdout) { should match /CREATE SCHEMA serverspec_test/ }
        its(:stdout) { should match /CREATE TABLE serverspec_test\.test/ }
        its(:stdout) { should match /INSERT INTO serverspec_test\.test/ }
        its(:stdout) { should match /DROP TABLE serverspec_test\.test/ }
        its(:stdout) { should match /DROP SCHEMA serverspec_test/ }
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Checking if the Elasticsearch logs contain queries executed with PGBouncer', :if => pgbouncer_enabled do
      describe command("curl -k -u admin:admin 'https://#{elasticsearch_host}:#{elasticsearch_api_port}/_search?pretty=true' -H 'Content-Type: application/json' -d '{\"size\":100,\"_source\":{\"includes\":\"message\"},\"query\":{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match_phrase\":{\"source\":\"/var/log/postgresql/postgresql-10-main.log\"}},{\"match_phrase\":{\"source\":\"/var/log/postgresql/postgresql.log\"}}],\"minimum_should_match\":1}}],\"filter\":{\"query_string\":{\"query\":\"*#{pg_user}*\"}}}}}'") do
        its(:stdout) { should match /GRANT ALL ON SCHEMA serverspec_test to #{pg_user}/ }
        its(:stdout) { should match /GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA serverspec_test to #{pg_user}/ }
        its(:stdout) { should match /CREATE TABLE serverspec_test\.pgbtest/ }
        its(:stdout) { should match /INSERT INTO serverspec_test\.pgbtest/ }
        its(:stdout) { should match /CREATE USER #{pg_user} WITH PASSWORD/ }
        its(:stdout) { should match /DROP USER #{pg_user}/ }
        its(:exit_status) { should eq 0 }
      end
    end

    describe 'Checking support for multiline messages' do
      describe command("curl -k -u admin:admin 'https://#{elasticsearch_host}:#{elasticsearch_api_port}/_search?pretty=true' -H 'Content-Type: application/json' -d '{\"size\":100,\"_source\":{\"includes\":\"message\"},\"query\":{\"bool\":{\"must\":[{\"bool\":{\"should\":[{\"match_phrase\":{\"source\":\"/var/log/postgresql/postgresql-10-main.log\"}},{\"match_phrase\":{\"source\":\"/var/log/postgresql/postgresql.log\"}}],\"minimum_should_match\":1}}],\"filter\":{\"query_string\":{\"query\":\"ADD AND COLUMN\"}}}}}'") do
        its(:stdout) { should match /ALTER TABLE serverspec_test\.test.*\\n\\t.*ADD COLUMN id.*\\n\\t.*ADD COLUMN name.*\\n\\t.*ADD COLUMN city.*\\n\\t.*ADD COLUMN description/ }
        its(:exit_status) { should eq 0 }
      end
    end

  end
end

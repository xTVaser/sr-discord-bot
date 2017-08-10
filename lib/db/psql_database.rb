# On a debian distro - sudo apt-get install libpq-dev
# On another distro - ??

require 'pg'
require 'dotenv'
require 'json'

Dotenv.load('vars.env')

# Documentation at https://deveiate.org/code/pg/
# GUI for postgreSQL run `docker run --rm -p 5050:5050 thajeztah/pgadmin4`
module RunTracker
  module PostgresDB
    # Format of ENV Variable is:
    # user:password@host:port/dbname
    databaseParams = ENV['DATABASE_URL'].sub('postgres://', '')
    databaseParams = databaseParams.split(':')

    username = databaseParams.first
    password = databaseParams[1].split('@').first
    host = databaseParams[1].split('@').last
    port = databaseParams[2].split('/').first
    dbname = databaseParams[2].split('/').last

    # Establish connection to PostgreSQL database
    Conn = PG.connect(user: username,
                      password: password,
                      host: host,
                      port: port,
                      dbname: dbname)

    # Called at this point manually to create the schema.
    # If the bot is expanded in the future, then we can either have a 'server'
    # table or create seperate DBs for each server.
    # This should be moved to a rake task rather than calling it from the bot
    # in the future
    def self.generateSchema
      # Generate tracked-games table

      createTrackedGamesCmd = 'CREATE TABLE IF NOT EXISTS public."tracked_games" (' \
                              '"game_id" character varying(255) NOT NULL,' \
                              '"game_alias" character varying(255) NOT NULL,' \
                              '"game_name" text NOT NULL,' \
                              '"announce_channel" bigint NOT NULL,' \
                              'categories jsonb,' \
                              'moderators jsonb,' \
                              'PRIMARY KEY ("game_id"))' \
                              'WITH (' \
                              'OIDS = FALSE);'
      createTrackedRunnersCmd = 'CREATE TABLE IF NOT EXISTS public."tracked_runners"(' \
                                '"user_id" character varying(255) NOT NULL,' \
                                '"user_name" character varying(255) NOT NULL,' \
                                '"historic_runs" jsonb,' \
                                '"num_submitted_wrs" integer, ' \
                                '"num_submitted_runs" integer, ' \
                                '"total_time_overall" bigint, ' \
                                'PRIMARY KEY ("user_id"))' \
                                'WITH (' \
                                'OIDS = FALSE);'
      createCommandPermissionsCmd = 'CREATE TABLE IF NOT EXISTS public."managers"(' \
                                    '"user_id" character varying(255) NOT NULL,' \
                                    '"access_level" integer NOT NULL,' \
                                    'PRIMARY KEY ("user_id"))' \
                                    'WITH (' \
                                    'OIDS = FALSE);'
      Conn.exec(createTrackedGamesCmd)
      Conn.exec(createTrackedRunnersCmd)
      Conn.exec(createCommandPermissionsCmd)
      return 'Tables Created Succesfully'
    rescue PG::Error => e
      return 'Table Creation Unsuccessful: ' + e.message
    end

    def self.destroySchema
      Conn.exec('DROP SCHEMA public CASCADE;')
      Conn.exec('CREATE SCHEMA public;')
      return 'Schema Destroyed!'
    rescue PG::Error => e
      return 'Schema Destruction Unsuccessful: ' + e.message
    end

    # TODO might not fully parse JSON?
    def self.getCurrentRunners()
      runners = Hash.new
      queryResults = PostgresDB::Conn.exec('SELECT * FROM public."tracked_runners"')

      queryResults.each do |runner|
        currentRunner = Runner.new(runner['user_id'], runner['user_name'])
        currentRunner.num_submitted_runs = Integer(runner['num_submitted_runs'])
        currentRunner.num_submitted_wrs = Integer(runner['num_submitted_wrs'])
        currentRunner.total_time_overall = Integer(runner['total_time_overall'])
        currentRunner.fromJSON(runner['historic_runs'])
        runners["#{runner['user_id']}"] = currentRunner # might have to do more than this
      end
      return runners
    end

    ##
    # Updates current runners with the new objects
    # primary key for runners is their ID field
    def self.updateCurrentRunners(currentRunners)

      # Update Statement
      PostgresDB::Conn.prepare('Update Current Runner', 'update public."tracked_runners"
        set user_id = $1, user_name = $2, historic_runs = $3, num_submitted_runs = $4, num_submitted_wrs = $5, total_time_overall = $6
        where user_id = $1')
      currentRunners.each do |key, runner|
        begin
          PostgresDB::Conn.exec_prepared('Update Current Runner', [runner.src_id, runner.src_name,
                                                                  JSON.generate(runner.historic_runs), runner.num_submitted_runs,
                                                                  runner.num_submitted_wrs, runner.total_time_overall])
        rescue Exception => e
          puts "#{e.message} #{e.backtrace}"
        end
      end
    end

    ##
    # Inserts brand new runners into DB
    def self.insertNewRunners(newRunners)

      # Update Statement
      PostgresDB::Conn.prepare('Insert New Runner', 'insert into public."tracked_runners"
        (user_id, user_name, historic_runs, num_submitted_runs, num_submitted_wrs, total_time_overall)
        values ($1, $2, $3, $4, $5, $6)')
      newRunners.each do |key, runner|
        begin
          PostgresDB::Conn.exec_prepared('Insert New Runner', [runner.src_id, runner.src_name,
                                                              JSON.generate(runner.historic_runs), runner.num_submitted_runs,
                                                              runner.num_submitted_wrs, runner.total_time_overall])
        rescue Exception => e
          puts "#{e.message} #{e.backtrace}"
        end
      end
    end # end of module
    # TODO test that adding with existing runners doesnt add duplicates
    # TODO test that all information it is gathering is accurate
    # TODO test that it doesnt break when adding the same game twice
    # TODO test adding a game without subcategories
    # TODO runners are having subcategories appended to them even if they havnt done a run of them

  end
end

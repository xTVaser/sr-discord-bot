require "sqlite3"
require 'json'

module RunTracker
  module SQLiteDB

    # Establish connection to SQLite database
    Conn = SQLite3::Database.new "db/database.db"
    Conn.results_as_hash = true

    # Called at this point manually to create the schema.
    # If the bot is expanded in the future, then we can either have a 'server'
    # table or create seperate DBs for each server.
    # This should be moved to a rake task rather than calling it from the bot
    # in the future
    def self.generateSchema
      # Generate tracked-games table
      createTrackedGamesCmd = 'CREATE TABLE IF NOT EXISTS "tracked_games" (' \
                              '"game_id" TEXT NOT NULL,' \
                              '"game_name" TEXT NOT NULL,' \
                              '"cover_url" TEXT,' \
                              '"announce_channel" INTEGER NOT NULL,' \
                              'PRIMARY KEY ("game_id"));'
      createCategoriesCmd = 'CREATE TABLE IF NOT EXISTS categories (' \
                            '"category_id" TEXT NOT NULL,' \
                            '"game_id" TEXT NOT NULL,' \
                            'name TEXT NOT NULL,' \
                            'rules TEXT,' \
                            'subcategories TEXT,' \
                            'current_wr_run_id TEXT,' \
                            'current_wr_time INTEGER,' \
                            'longest_held_wr_id TEXT,' \
                            'longest_held_wr_time INTEGER,' \
                            'number_submitted_runs INTEGER,' \
                            'number_submitted_wrs INTEGER,' \
                            'PRIMARY KEY ("category_id", "game_id"));'
      createModeratorsCmd = 'CREATE TABLE IF NOT EXISTS moderators (' \
                            '"src_id" TEXT NOT NULL,' \
                            '"game_id" TEXT NOT NULL,' \
                            '"src_name" TEXT NOT NULL,' \
                            '"discord_id" INTEGER NOT NULL,' \
                            '"should_notify" INTEGER NOT NULL,' \
                            '"secret_key" TEXT NOT NULL,' \
                            '"last_verified_run_date" INTEGER,' \
                            '"total_verified_runs" INTEGER NOT NULL,' \
                            '"past_moderator" INTEGER NOT NULL,' \
                            'PRIMARY KEY ("src_id", "game_id"));'
      createTrackedRunnersCmd = 'CREATE TABLE IF NOT EXISTS "tracked_runners" (' \
                                '"user_id" TEXT NOT NULL,' \
                                '"user_name" TEXT NOT NULL,' \
                                '"avatar_url" TEXT,' \
                                '"historic_runs" TEXT,' \
                                '"num_submitted_wrs" INTEGER, ' \
                                '"num_submitted_runs" INTEGER, ' \
                                '"total_time_overall" INTEGER, ' \
                                'PRIMARY KEY ("user_id"));'
      createCommandPermissionsCmd = 'CREATE TABLE IF NOT EXISTS managers (' \
                                    '"user_id" TEXT NOT NULL,' \
                                    '"access_level" INTEGER NOT NULL,' \
                                    'PRIMARY KEY ("user_id"));'
      createAliasTable = 'CREATE TABLE IF NOT EXISTS aliases (' \
                         '"alias" TEXT NOT NULL,' \
                         '"type" TEXT NOT NULL,' \
                         '"id" TEXT NOT NULL UNIQUE,' \
                         'PRIMARY KEY ("alias", "type"));'
      createResourcesTable = 'CREATE TABLE IF NOT EXISTS resources (' \
                             '"resource" TEXT NOT NULL,' \
                             '"game_alias" TEXT NOT NULL,' \
                             '"content" TEXT NOT NULL,' \
                             'PRIMARY KEY ("resource", "game_alias"));'
      createNotificationTable = 'CREATE TABLE IF NOT EXISTS notifications(' \
                                '"run_id" TEXT NOT NULL,' \
                                'PRIMARY KEY ("run_id"));'
      createAnnouncementsTable = 'CREATE TABLE IF NOT EXISTS announcements(' \
                                 '"run_id" TEXT NOT NULL,' \
                                 'PRIMARY KEY ("run_id"));'
      createSettingsTable = 'CREATE TABLE IF NOT EXISTS settings(' \
                            '"allowed_game_list" TEXT NOT NULL,' \
                            '"stream_channel_id" TEXT NOT NULL,' \
                            '"streamer_role" TEXT NOT NULL,' \
                            '"exclude_keywords" TEXT);'
      # information tables
      Conn.execute(createTrackedGamesCmd)
      Conn.execute(createCategoriesCmd)
      Conn.execute(createModeratorsCmd)
      Conn.execute(createTrackedRunnersCmd)
      Conn.execute(createAliasTable)
      Conn.execute(createResourcesTable)
      # config tables
      Conn.execute(createCommandPermissionsCmd)
      Conn.execute(createNotificationTable)
      Conn.execute(createAnnouncementsTable)
      Conn.execute(createSettingsTable)
      Stackdriver.log("Tables Created Successfully")
      return 'Tables Created Succesfully'
    rescue SQLite3::Exception => e
      Stackdriver.exception(e)
      return 'Table Creation Unsuccessful'
    end

    def self.destroySchema
      Conn.execute('DROP TABLE IF EXISTS tracked_games')
      Conn.execute('DROP TABLE IF EXISTS categories')
      Conn.execute('DROP TABLE IF EXISTS moderators')
      Conn.execute('DROP TABLE IF EXISTS tracked_runners')
      Conn.execute('DROP TABLE IF EXISTS resources')
      Conn.execute('DROP TABLE IF EXISTS aliases')
      Conn.execute('DROP TABLE IF EXISTS managers')
      Conn.execute('DROP TABLE IF EXISTS notifications')
      Conn.execute('DROP TABLE IF EXISTS announcements')
      Conn.execute('DROP TABLE IF EXISTS settings')
      Stackdriver.log("Tables Dropped")
      return 'Schema Destroyed!'
    rescue SQLite3::Exception => e
      Stackdriver.exception(e)
      return 'Schema Destruction Unsuccessful'
    end

    def self.dontDropManagers
      Conn.execute('DROP TABLE IF EXISTS tracked_games')
      Conn.execute('DROP TABLE IF EXISTS categories')
      Conn.execute('DROP TABLE IF EXISTS moderators')
      Conn.execute('DROP TABLE IF EXISTS tracked_runners')
      Conn.execute('DROP TABLE IF EXISTS resources')
      Conn.execute('DROP TABLE IF EXISTS aliases')
      Stackdriver.log("Dropped Every Non-Manager & Notification Table")
    end

    def self.getCurrentRunners
      runners = {}
      begin
        queryResults = Conn.execute('SELECT * FROM "tracked_runners"')
        queryResults.each do |runner|
          currentRunner = Runner.new(runner['user_id'], runner['user_name'])
          currentRunner.avatar_url = runner['avatar_url']
          currentRunner.num_submitted_runs = Integer(runner['num_submitted_runs'])
          currentRunner.num_submitted_wrs = Integer(runner['num_submitted_wrs'])
          currentRunner.total_time_overall = Integer(runner['total_time_overall'])
          currentRunner.fromJSON(runner['historic_runs'])
          runners[(runner['user_id']).to_s] = currentRunner
        end
      rescue SQLite3::Exception => e
        Stackdriver.exception(e)
      end
      return runners
    end

    def self.getCurrentRunner(runnerID)
      currentRunner = nil
      begin
        runner = Conn.execute("SELECT * FROM tracked_runners WHERE user_id = ?", runnerID).first
        if runner == nil
          return nil
        end
        currentRunner = Runner.new(runner['user_id'], runner['user_name'])
        currentRunner.avatar_url = runner['avatar_url']
        currentRunner.num_submitted_runs = Integer(runner['num_submitted_runs'])
        currentRunner.num_submitted_wrs = Integer(runner['num_submitted_wrs'])
        currentRunner.total_time_overall = Integer(runner['total_time_overall'])
        currentRunner.fromJSON(runner['historic_runs'])
      rescue SQLite3::Exception => e
        Stackdriver.exception(e)
      end
      return currentRunner
    end

    # TODO: historic runs table needs to be implemented, as of right now leaving it JSON

    ##
    # Updates current runners with the new objects
    # primary key for runners is their ID field
    def self.updateCurrentRunners(currentRunners)
      # Update Statement
      currentRunners.each do |_key, runner|
        updateCurrentRunner(runner)
      end # end of loop
    end

    ##
    # Updates current runner with the new objects
    # primary key for runner is their ID field
    def self.updateCurrentRunner(runner)
      # Update Statement
      begin
        Conn.execute('update "tracked_runners"
                      set user_id = ?,
                          user_name = ?, 
                          historic_runs = ?,
                          num_submitted_runs = ?, 
                          num_submitted_wrs = ?, 
                          total_time_overall = ?
                      where user_id = ?',
                      runner.src_id,
                      runner.src_name,
                      JSON.generate(runner.historic_runs),
                      runner.num_submitted_runs,
                      runner.num_submitted_wrs,
                      runner.total_time_overall,
                      runner.src_id)
      rescue SQLite3::Exception => e
        Stackdriver.exception(e)
      end # end of transaction
    end # end of loop

    ##
    # Inserts brand new runners into DB
    def self.insertNewRunners(newRunners)
      # Update Statement
      newRunners.each do |_key, runner|
        insertNewRunner(runner)
      end
    end

    # TODO: perhaps these should be moved into the models as static methods?

    ##
    # Inserts brand new runner into DB
    def self.insertNewRunner(runner)
      # Update Statement
      begin
        Conn.execute('insert into "tracked_runners"
                        (user_id, 
                        user_name, 
                        avatar_url,
                        historic_runs, 
                        num_submitted_runs, 
                        num_submitted_wrs, 
                        total_time_overall)
                      values (?, ?, ?, ?, ?, ?, ?)',
                      runner.src_id, 
                      runner.src_name, 
                      runner.avatar_url,
                      JSON.generate(runner.historic_runs), 
                      runner.num_submitted_runs, 
                      runner.num_submitted_wrs,
                      runner.total_time_overall)
      rescue Exception => e
        Stackdriver.exception(e)
      end
    end

    ##
    # Insert new aliases into the table
    def self.insertNewAliases(newAliases)
      # Update Statement
      newAliases.each do |key, value|
        insertNewAlias(key, value)
      end
    end # end of self.insertNewAliases

    def self.insertNewAlias(key, value)
      begin
        Conn.execute('insert into "aliases"
                        (alias, 
                        type, 
                        id)
                      values (?, ?, ?)',
                      key,
                      value.first,
                      value.last)
      rescue SQLite3::Exception => e
        Stackdriver.exception(e)
        return false
      end
      return true
    end

    def self.insertNewTrackedGame(trackedGame)
      begin
        Conn.transaction
        Conn.execute('insert into "tracked_games"
                        ("game_id", 
                        "game_name", 
                        "cover_url",
                        "announce_channel")
                      values (?, ?, ?, ?)',
                      trackedGame.id,
                      trackedGame.name,
                      trackedGame.cover_url,
                      trackedGame.announce_channel.id)
        categories = trackedGame.categories
        categories.each do |key, category|
          Conn.execute('insert into categories
                          ("category_id",
                          "game_id",
                          name,
                          rules,
                          subcategories,
                          "current_wr_run_id",
                          "current_wr_time",
                          "longest_held_wr_id",
                          "longest_held_wr_time",
                          "number_submitted_runs",
                          "number_submitted_wrs")
                          values (?,?,?,?,?,?,?,?,?,?,?)',
                          key, # TODO: why use key?
                          trackedGame.id,
                          category.category_name,
                          category.rules,
                          JSON.generate(category.subcategories),
                          category.current_wr_run_id,
                          category.current_wr_time,
                          category.longest_held_wr_id,
                          category.longest_held_wr_time,
                          category.number_submitted_runs,
                          category.number_submitted_wrs)
        end
        moderators = trackedGame.moderators
        moderators.each do |key, moderator|
          Conn.execute('insert into moderators
                          ("src_id",
                          "game_id",
                          "src_name",
                          "discord_id",
                          "should_notify",
                          "secret_key",
                          "last_verified_run_date",
                          "total_verified_runs",
                          "past_moderator")
                        values (?,?,?,?,?,?,?,?,?)',
                        moderator.src_id,
                        trackedGame.id,
                        moderator.src_name,
                        moderator.discord_id,
                        (moderator.should_notify ? 1 : 0),
                        moderator.secret_key,
                        moderator.last_verified_run_date.to_s,
                        moderator.total_verified_runs,
                        (moderator.past_moderator ? 1 : 0))
        end
        Conn.commit
      rescue SQLite3::Exception => e
        Stackdriver.exception(e)
        Conn.rollback
        return false
      end
      return true
    end

    ##
    # Given an alias, return the ID equivalent
    # TODO: add type argument here and fix usages throughout codebase
    def self.findID(theAlias)
      results = Conn.execute("SELECT * FROM aliases WHERE alias=?", theAlias)
      if results.length < 1
        return nil
      end
      return results.first['id']
    end

    ##
    # Get tracked game by alias, returns object representation
    def self.getTrackedGame(game_id)
      gameResults = Conn.execute('SELECT * FROM "tracked_games" WHERE "game_id"=?', game_id)
      if gameResults.length < 1
        return nil
      end
      gameResult = gameResults.first
      game = TrackedGame.new(gameResult['game_id'], 
                              gameResult['game_name'], 
                              gameResult['cover_url'],
                              getCategories(gameResult['game_id']), 
                              getModerators(gameResult['game_id']))
      game.announce_channel = gameResult['announce_channel']
      return game
    end

    ##
    # Get tracked games, returns object representation
    def self.getTrackedGames
      gameResults = Conn.execute("SELECT * FROM tracked_games")
      if gameResults.length < 1
        return nil
      end
      games = Array.new
      gameResults.each do |gameResult|
        game = TrackedGame.new(gameResult['game_id'], 
                               gameResult['game_name'], 
                               gameResult['cover_url'],
                               getCategories(gameResult['game_id']), 
                               getModerators(gameResult['game_id']))
        game.announce_channel = gameResult['announce_channel']
        games.push(game)
      end
      return games
    end

    ##
    # Get the associated categories and moderators for each game
    def self.getCategories(game_id)
      categoryResults = Conn.execute("SELECT * FROM categories WHERE game_id = ?", game_id)
      categories = Hash.new
      categoryResults.each do |row|
        category = Category.new(
          row['category_id'],
          row['name'],
          row['rules'],
          row['subcategories']
        )
        category.current_wr_run_id = row['current_wr_run_id']
        category.current_wr_time = row['current_wr_time']
        category.longest_held_wr_id = row['longest_held_wr_id']
        category.longest_held_wr_time = row['longest_held_wr_time']
        category.number_submitted_runs = row['number_submitted_runs']
        category.number_submitted_wrs = row['number_submitted_wrs']
        categories[row['category_id']] = category
      end
      return categories
    end # end of getCategories

    ##
    #
    def self.getModerators(game_id)
      moderatorResults = Conn.execute("SELECT * FROM moderators WHERE game_id = ?", game_id)
      moderators = Hash.new
      moderatorResults.each do |row|
        moderator = Moderator.new(row['src_id'], row['src_name'])
        moderator.discord_id = row['discord_id']
        moderator.should_notify = row['should_notify']
        moderator.secret_key = row['secret_key']
        if row['last_verified_run_date'] != ""
          moderator.last_verified_run_date = Date.strptime(row['last_verified_run_date'], '%Y-%m-%d')
        end
        moderator.total_verified_runs = row['total_verified_runs']
        moderator.past_moderator = row['past_moderator']
        moderators[row['src_id']] = moderator
      end
      return moderators
    end

    ##
    # Updates tracked game based on it's ID
    def self.updateTrackedGame(game)
      Conn.execute("update tracked_games 
                    set game_id = ?, 
                        game_name = ?,
                        cover_url = ?,
                        announce_channel = ? 
                    where game_id = ?",
                    game.id, 
                    game.name, 
                    game.cover_url, 
                    game.announce_channel, 
                    game.id)
    end

    ##
    # Gets the game name alias from a category alias
    def self.categoryAliasToGameID(theAlias)
      results = Conn.execute("SELECT * FROM aliases WHERE alias=?", theAlias)
      if results.length < 1
        return nil
      end
      return self.findID(results.first['alias'].split('-').first)
    end # end of func

    ##
    # Initialize everyones permissions
    def self.initPermissions
      Stackdriver.log("Initializing Permissions")
      begin
        userPermissions = Conn.execute('select * from managers') # Grab each user ID from the database
        userPermissions.each do |user|
          RTBot.set_user_permission(Integer(user['user_id']), Integer(user['access_level']))
        end
      rescue SQLite3::Exception => e
        Stackdriver.exception(e)
      end
    end # end of func
  end # end of module
end

require 'sinatra'
require 'sinatra/reloader'
require 'mysql2'
require "mysql2-cs-bind"
require "pry"
#TODO require して機能の実装は別ファイルにしたい みにくい

set :public_folder, 'public'
enable :sessions
# ======================

def client
  @db ||= Mysql2::Client.new(
    host:     ENV['DB_HOST'] || 'localhost',
    port:     ENV['DB_PORT'] || '3306',
    username: ENV['DB_USERNAME'] || 'root',
    password: ENV['DB_PASSWORD'] || '',
    database: ENV['DB_DATABASE'] || 'factoryApp',
  )
end

# ======================
def is_login()
  if session[:user_id].nil?
    redirect '/'
  end
  status_header()
end
# =======headerの表示に必要な情報
def status_header()
  @num = session[:user_status].divmod(12)
  @money = session[:lastmoney] / 10000 #万円表記に変換
  @oerder = session[:product_name]
  @login_user_name = session[:user_name]
  puts @login_user_name
  enumber = client.xquery("SELECT COUNT(*) FROM employees where user_id = ? and retired_flag = ?;",session[:user_id],0)
  # puts enumber.class
  enumber.each do |e| #もっとスマートに出来る方法ありそう
    @enumber = e["COUNT(*)"]
    session[:enumber] = @enumber
  end
end

def boss_comand() #２年目から使える機能とか
  if @num[1] > 1
    session[:boss] = "工場長がきました。従業員の辞める確率が増大します"
  end
end
# ======================
get '/info' do
  is_login() #必要情報
  @employees = client.xquery("select * from employees where user_id = ? and retired_flag = ?;"\
    ,session[:user_id],0)
  @retired = client.xquery("select * from employees where user_id = ? and retired_flag = ?;",session[:user_id],1)

#3つのテーブルのがっちゃんこができん
#TODO できると表示できる内容がよくなるからやりたい
  # @aa = client.xquery("select * from (select * from e_make_product inner join employees on e_make_product.employee_id\
  #   = employees.id where employees.user_id = ?) inner join products on e_make_product.product_id = products.id;", session[:user_id])

  # @aa = client.xquery("select * from e_make_product inner join employees on e_make_product.employee_id\
  #    = employees.id where employees.user_id = ?;", session[:user_id])
  # puts @aa
  # @aa.each do |a|
  #   puts a
  # end

  @inform = session[:kaiko]
  session[:kaiko] =nil
  erb :info
end

get '/kaiko/:id' do
  client.xquery("update employees set retired_flag = ? where id = ?;",1,params[:id])
  #TODO 名前を取得したいけどうまくいかない、、　でもやらなくていいことだからスルーしよう
  redirect '/info'
end

# ======================
get '/stock' do
  is_login()

  # TODO ひっぱるための条件を記入する
  @materials = client.xquery("select * from product_materials inner join user_stocks on product_materials.id = user_stocks.product_materials where user_stocks.user_id = ?;", session[:user_id])
  @products = client.xquery("select * from products")
  erb :stock
end

# ======================
get '/home' do
  is_login  #ログイン確認

  @name = session[:e_name]
  @inform = session[:inform]
  session[:inform] =nil
  session[:e_name]=nil
  erb :index
end

# ======================
def check_custmer
  if session[:product_id].nil? #お客さんに確認しに行ったか確認
    session[:inform] = "お客さんにオーダーを聞きに行ってください"
    redirect '/home'
  end
end

get '/susumeru' do
  is_login #ログイン確認
  check_custmer #お客さん確認
  peple_count = 0
  @month_money = 0
  product = client.xquery("SELECT * FROM products where id = ? ;", session[:product_id]).first
  @arr_var = []
  @yameta = []
  #--------userの従業員を確認して売り上げの計算とどの従業員が何を何台作ったか計算する
  employees = client.xquery("select * from employees where user_id = ? and retired_flag = ? and skill >= ?;",session[:user_id],0,product["need_skill"])
  employees.each do | employee|
    peple_count += 1
    sum_make = 30 / product["need_process"] * employee["ability"]
    @month_money += sum_make * product["price"]
    array1 = []
    array1.push(employee["name"], product["name"], sum_make)
    @arr_var.push(array1)

    x = client.xquery("select * from e_make_product where employee_id = ? and product_id = ?;",employee["id"],product["id"]).first
    if x
      client.xquery("update e_make_product set make_numbers = ? where employee_id = ? and product_id = ?;",sum_make + x["make_numbers"], employee["id"],product["id"])
    else
      client.xquery("insert into e_make_product values(null,?,?,?);", employee["id"], product["id"], sum_make)
    end


    #-------使用する部品と作成した台数を計算してupdateする
    midle = client.xquery("select * from middle_table where product_id = ?;",session[:product_id])
    midle.each do |search|
      stocks = client.xquery("select * from user_stocks where user_id = ? and product_materials = ?;",session[:user_id],search["material_id"]).first
      subtraction = stocks["stock_numbers"] - search["required_number"] * sum_make
      puts "計算結果を確認"
      puts subtraction
      client.xquery("update user_stocks set stock_numbers = ? where user_id = ? and product_materials = ?;", subtraction, session[:user_id],search["material_id"])
    end

    #----------従業員の辞めるリスクの計算を　工場長リスクもあるよ
    risk = 1
    tple = 70 - risk * 10 * employee["ability"].to_i
    random_choise = rand(tple) #0~2でバラバラ
    if random_choise < 8 then
      @yameta.push(employee["name"])
      client.xquery("update employees set retired_flag = ? where id = ?;",1,employee["id"])
    end

  end
  @jinkenhi = peple_count * 200000
  @base_maney = 3000000
  session[:lastmoney] = session[:lastmoney] + @month_money - @jinkenhi - @base_maney
  @month_money /= 10000
  @jinkenhi /= 10000
  @base_maney /= 10000
  session[:user_status] += 1 #statusの更新 １ヶ月すぎる
  client.xquery("insert into users_history values(null,?,?,?,?,?);",session[:user_id],session[:user_status], session[:lastmoney], 0, DateTime.now)
  client.xquery("update users set status = ? where id = ?;", session[:user_status],session[:user_id])
  session[:product_id] = nil
  session[:product_name] = nil

  erb :susumeru
end

get '/customer' do
  is_login()

  if session[:product_name] #"sessionに入ってる場合"
    @res = session[:product_name]
  else                     #"sessionに入ってない場合"
    productNumber = [1,1,1,1,2,2,2,3,3,4].sample(1)
    @res = client.xquery("SELECT * FROM products where id = ? ;", productNumber).first
    session[:product_id] = @res["id"]
    session[:product_name] = @res["name"]
    @res = @res["name"]
  end

  erb :customer
end


# ======================
get '/buy' do
  is_login() #必要情報
  @materials = client.xquery("select * from product_materials inner join user_stocks on product_materials.id = user_stocks.product_materials where user_stocks.user_id = ?;", session[:user_id])

  @buy = session[:buy]
  session[:buy] = nil
  erb :buy
end

post '/buy' do
  #TODO 手持ち金からどれだけ購入できるか計算するのも、あとで
  counts = params[:buy_count].to_i #個数
  price = params[:m_price].to_i    #typeの値段
  type = params[:m_type].to_i      #typeの番号
  last_stock = params[:last_stock].to_i #前回の個数
  money = session[:lastmoney] #現在の資産
  sum_price = counts * price       #購入金額
  sum_coutns = counts + last_stock #手持ちの合計アップデート

  if money > sum_price
    session[:lastmoney] -= sum_price
    puts session[:lastmoney]
    client.xquery("update user_stocks set stock_numbers = ? where user_id = ? and product_materials = ?",sum_coutns, session[:user_id], type)
    client.xquery("update users_history set asset = ? where user_id = ? order by id desc limit 1;",session[:lastmoney], session[:user_id])
    session[:buy] = "購入しました"
  else
    session[:buy] = "お金が足りません。入力しなおしてください"
  end

  redirect '/buy'
end

# ======================
get '/yatou' do
  is_login #ログイン確認
  erb :yatou
end
# =====
post '/yatou' do
  name = ["饒波","知名","玉寄","下地","比嘉","宮城","座喜味","親里","屋我","玉城","前城","大城","鈴木","sabo","仲宗根","山内","高良","森","がけお"].sample(1)
  gender= ["man","woman"].sample
  skill = rand(3) #0~2でバラバラ
  ability = 2 + rand(3) #2~4の能力値になる
  client.xquery("insert into employees values (null,?,?,?,?,?,default,default,?);", name, session[:user_id],gender,skill,ability,DateTime.now)
  new_id =  client.last_id #最後のidを取得する!!
  #作業員の作った数を全部カウントする
  material_numbers = client.xquery("SELECT COUNT(*) FROM products;")
  material_numbers.each do |numbers|
    numbers["COUNT(*)"].times do |number|
      client.xquery("insert into e_make_product values(null,?,?,default);",new_id,number+1)
    end
  end

  session[:e_name] = name
  redirect '/home'
end

# ======================
get '/' do
  @page_info = session[:page_info]
  session[:page_info] = nil
  erb :login, :layout => nil
end

# ====
get '/logout' do
  session[:user_id] = nil
  session[:user_name] = nil
  session[:user_status] = nil
  session[:enumber] = nil
  session[:lastmoney] = nil

  redirect '/'
end

# ====
post '/login' do
  res = client.xquery("SELECT * FROM users where name = ? and pass = ?;", params[:login_name],params[:login_pass]).first
  if res
    session[:user_id] = res['id']
    session[:user_name] = res['name']
    session[:user_status] = res['status']
    #userの前回の資産を計算する
    aa = client.xquery("SELECT asset FROM users_history where user_id = ? order by id desc limit 1;", session[:user_id])
    aa.each do |a|
      session[:lastmoney] = a["asset"]
    end

    redirect '/home'
  else
    session[:page_info] = "ユーザー名orパスワードが間違ってます。もう一度入力してください"
    redirect '/'
  end
end
# ======================

get '/new_acount' do
  @page_info = session[:page_info]
  session[:page_info] = nil

  erb :new_acount, :layout => nil
end
# =====
post '/new_acount' do
  res = client.xquery("select * from users where name = ?;",params[:new_name]).first

  if res
    session[:page_info] = "ユーザー名がすでに使用されています。変更よろしくお願いします。"
  else
    #usersに追加
    client.xquery("insert into users values (null,?,?,default,?,?);", params[:new_name], params[:new_pass],DateTime.now,DateTime.now)
    new_id =  client.last_id #最後のidを取得する!!
    #historyに追加
    client.xquery("insert into users_history values(null,?,default,default,default,?);",new_id,DateTime.now)

    #user_stockも追加 materialの数値を確認して初期値を入力
    material_numbers = client.xquery("SELECT COUNT(*) FROM product_materials;")
    material_numbers.each do |numbers|
      numbers["COUNT(*)"].times do |number|
        client.xquery("insert into user_stocks values(null,?,?,default);",new_id,number+1)
      end
    end

    session[:page_info] = "新規登録完了しました"
    redirect '/'
  end
  redirect '/new_acount'
end

# ======================

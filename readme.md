# ECS を利用したBlue/Green Depoyment サンプル

以下のことを実施できるサンプルです。
- Cloud9 上で、シンプルなSpring Boot Web Application をDokcer イメージにビルドし、Dokcer コンテナとして動かし、ECR にリポジトリを作成してイメージを格納する
- ビルドしたDokcer イメージをECS を利用しFargate 上で動かし、Blue/Green デプロイを実施する

*重要*: こちらのサンプルを実行する場合、AWS 料金が発生する可能性があります。サンプルの実行が終了したら適切にリソースの削除をしてください。

# 初期構成

## 初期インフラの構成

templates/multiaz-vpc-alb.yaml をダウンロードして、任意のリージョンにてCloudFormation を利用して任意のStack 名でサンプル動作用のインフラを作成します。
ECS を利用してコンテナを動かすためのVPC とALB 環境が自動的に構成されます。

## Cloud9 の起動

任意のリージョンにてCloud9 を起動します。
- インスタンスタイプ: m3.small 以上を推奨
- Platform: Amazon Linux 2

## Amazon Corretto 11 およびMaven のインストール
Cloud9 でTerminal を開き、以下のコマンドを実行します。

Amazon Corretto 11 のインストール
```
wget https://corretto.aws/downloads/latest/amazon-corretto-11-x64-linux-jdk.rpm

sudo rpm -ihv /home/ec2-user/environment/amazon-corretto-11-x64-linux-jdk.rpm
```

Maven のインストール
```
sudo wget http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O /etc/yum.repos.d/epel-apache-maven.repo
sudo sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
sudo yum install -y apache-maven
```

- 参考URL : [Maven を使用して設定する](https://docs.aws.amazon.com/ja_jp/cloud9/latest/user-guide/sample-java.html#sample-java-sdk-maven)



# Docker イメージの作成及びCloud9 上での実行、ECR へのPush


## コードのダウンロードおよびコンパイル

以下のコマンドを実行して、コードをダウンロードします。

```
git clone https://github.com/tomofuminijo/aws-ecs-bluegreen-deployment-sample.git
cd aws-ecs-bluegreen-deployment-sample
mvn package
```

## Docker イメージを作成し、ローカルでテスト実行する

以下のコマンドを実行して、Docker イメージをビルドします。
　
```
cd /home/ec2-user/environment/aws-ecs-bluegreen-deployment-sample
docker build --tag java-webapp .
```

以下のコマンドを実行して、コンテナを起動しテストします。

```
docker run --rm -p 8080:8080 \
  --env AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)\
  --env AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key) \
  --env AWS_SESSION_TOKEN=$(aws configure get aws_session_token) \
  java-webapp:latest
```

上記コマンドを実行すると、Terminarl 右上に、"Your code is running at XXX" といったメッセージが表示されますので、そのURL をクリックするとWeb アプリケーションの画面のテストができます。  
"Hello! Ver: 1.0.0-Blue" という画面が表示されれば正常に動作しています。


## ECR にリポジトリを作成してイメージを登録する

まず、ECR 上にリポジトリを作成します。  
以下のコマンドを実行します。

```
aws ecr create-repository --repository-name ecssample

```

以下のような内容が表示されます。"repositoryUri" をコピーして手元に控えておきます。

```
{
    "repository": {
        "repositoryUri": "<your_account_id>.dkr.ecr.<your_account_id>.amazonaws.com/ecssample", 
        "imageScanningConfiguration": {
            "scanOnPush": false
        }, 
        "encryptionConfiguration": {
            "encryptionType": "AES256"
        }, 
        "registryId": "<your_account_id>", 
        "imageTagMutability": "MUTABLE", 
        "repositoryArn": "arn:aws:ecr:<your_region>:<your_account_id>:repository/ecssample", 
        "repositoryName": "ecssample", 
        "createdAt": 1625234173.0
    }
}
```

以下のコマンドを実行し、ローカル上でビルドしたイメージにリモートリポジトリのURI を指定し、  
後続のBlue/Green デプロイを考慮して、blue というバージョンでタグ付けしておきます。

```
docker tag java-webapp <your_account_id>.dkr.ecr.<your_region>.amazonaws.com/ecssample:blue
```

以下のコマンドを実行すると、ローカル上のイメージにリポジトリURI とタグが付与されていることが確認できます。

```
docker images
```

次に、先ほど作成したECR リポジトリにイメージをPush します。  
  
まずは以下のコマンドを実行し、プライベートなECR リポジトリにログインします。
<your_account_id> と <your_region> を適宜変更してからコマンドを実行します。

```
aws ecr get-login-password --region <your_region> | docker login --username AWS --password-stdin <your_account_id>.dkr.ecr.<your_region>.amazonaws.com
```

"Login Succeeded" と表示されれば正常に実行できています。  

次に、以下のコマンドを実行してリポジトリにイメージをPush します。  
<your_account_id> と <your_region> を適宜変更してからコマンドを実行します。


```
docker push <your_account_id>.dkr.ecr.<your_region>.amazonaws.com/ecssample:blue
```

正常にPush できたら、マネジメントコンソールでECR 上のリポジトリを確認してみてください。


# Dokcer イメージをECS を利用しFargate 上で動かし、Blue/Green デプロイを実施する

ECR 上にPush したコンテナイメージをECS を利用してFargate 上で動かします。またその際にALB と連携してロードバランシングさせます。  
またCodeDeploy と連携して、Blue/Green デプロイを実施します。

## 事前のIAM ロールの作成

CodeDeploy とECS が連携する際に必要となるIAM ロールを作成します。  
作成手順は以下の内容を確認してください。
- [Amazon ECS CodeDeploy IAM Role - Amazon Elastic Container Service](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/codedeploy_IAM_role.html)


## ECS の構成

### ECS タスク定義を作成


- マネージメントコンソールにて、ECS サービスにアクセスします。
- ナビゲーションペインにて、"タスク定義" をクリックします。
- "新しいタスク定義の作成" をクリックします。
- タスク定義の設定内容
  - Fargate を選択して、"次のステップ"
  - タスクとコンテナの定義の設定 にて以下を入力
      - タスク定義名： sampletask
      - タスクロール：  DevOpsECSTaskDemoRole を含むロール  ※CFn にて作成済み
      - タスク実行ロール： ecsTaskExecutionRole (初回実施時は、自動で作成される)
      - タスクサイズ： 1GB / 0.5 vCPU
      - コンテナの追加 をクリック
        - コンテナ名： java-web-app
        - イメージ： <your_account_id>.dkr.ecr.<your_region>.amazonaws.com/ecssample:blue
        - メモリ制限(MiB)： ソフト制限 1024 
        - ポートマッピング: コンテナポート： 8080  プロトコル: tcp
        - CPU ユニット数: 512 cpu
        - 上記以外はデフォルトのままで、[追加]ボタンをクリック
      - 以上で、[作成] ボタンをクリック
  - タスク定義の表示をクリック


### ECS クラスターを作成

- ナビゲーションペインにて、"クラスター" をクリック
- "クラスターの作成" ボタンをクリック
- "ネットワークのみ" を選択して"次のステップ"
- "クラスターの設定" にて以下を定義
  - クラスター名: ECSSampleClsuter
  - その他はデフォルトのままで、"作成" ボタンをクリック
- "クラスターの表示" ボタンをクリック

### サービス定義を作成

- ECSSampleClsuter 画面の下側の"サービス" タブにて、"作成" ボタンをクリック
- "サービスの設定" 画面にて以下を入力
  - 起動タイプ: Fargte
  - タスク定義: sampletask
  - リビジョン: 1 (latest)
  - サービス名: ECSSampleService
  - タスクの数: 4
  - デプロイメントタイプ: "Blue/Green デプロイメント (AWS CodeDeploy を使用)" にチェック
  - CodeDeploy のサービスロール*: 先ほど作成したCodeDeploy 用のIAM ロール ("ecsCodeDeployRole")
  - その他の項目はデフォルトのままで、"次のステップ" ボタンをクリック
- "ネットワーク構成" 画面にて以下を入力
  - クラスターVPC: 10.0.1.0/16 のものを選択 （CFn スタック名が付与されている物）
  - サブネット: PublicSubnet1 および 2 を選択
  - セキュリティグループ: "編集" ボタンをクリックし、"既存のセキュリティグループ" から"ECSTaskSecurityGroup" が名前に入っている物を選択し、"保存" ボタンをクリク
  - パブリックIP の自動割当: "ENABLED" (Defaultのまま)
  - "ロードバランシング" にて以下を設定
    - ロードバランサーの種類: Application Load Balancer
    - ヘルスチェックの猶予期間(ロードバランシングの上の方にある): 60 (秒)
    - ロードバランサー名: CFn で作成されたロードバランサーを選択
  - "ロードバランス用のコンテナ" にて以下を設定
    - コンテナ名: ポート: java-web-app:8080:8080 -> "ロードバランサに追加" ボタンをクリック
    - プロダクションリスナーポート*: 80:HTTP
    - テストリスナーポート: 8080:HTTP
  - "Additional configuration" にて以下を設定
    - ターゲットグループ 1 の名前*: "target1" が含まれるものを選択(しばらくカーソルを当てると確認可能)
    - ターゲットグループ 2 の名前*: "target2" が含まれるものを選択(しばらくカーソルを当てると確認可能)
  - その他はデフォルトのままで、"次のステップ" ボタンをクリック
- "Auto Scaling (オプション)" 画面では何も変更せずに"次のステップ" ボタンをクリック
- "確認" 画面で、"サービスの作成" ボタンをクリック

### 動作確認

CloudFormation のスタックの出力のELBEndopoint を確認します。  
出力されているURL をコピーして、ブラウザでアクセスします。
Cloud9 上で実行した際と同じ画面が出れば正常に動作しています。


### Blue/Green デプロイメントの確認

Cloud9 にて作業を行います。 

src/resource/templates/index.html
を開き、"Ver: 1.0.0-Blue" となっている箇所を、"Ver: 2.0.0-Green" と変更しファイルを保存します。

以下のコマンドを実行します。

```
cd /home/ec2-user/environment/aws-ecs-bluegreen-deployment-sample
mvn package
docker build --tag java-webapp .
docker tag java-webapp <your_account_id>.dkr.ecr.<your_region>.amazonaws.com/ecssample:green
docker push <your_account_id>.dkr.ecr.<your_region>.amazonaws.com/ecssample:green
```

### タスク定義を変更

ECS 画面にて、タスク定義から"sampletask" にチェックを入れて、"新しいリビジョンの作成" をクリックします。  

- コンテナの定義 まで画面を下にスクロール
- "java-web-app" リンクをクリック
- "イメージ"をGreen のイメージURIに変更
  - <your_account_id>.dkr.ecr.<your_region>.amazonaws.com/ecssample:green
- "更新" ボタンをクリック
- "作成" ボタンをクリック
- "sampletask:2" が作成される

### サービスの更新
- クラスター -> ECSSampleClsuter -> "ECSSampleService2" にチェックを入れて"更新" ボタン
- タスク定義: リビジョン: 2(latest) に変更
- その他は更新しないため、"ステップ 5: 確認" まで"次のステップ" ボタンをクリック
- "サービスの更新" ボタンをクリック

### CodeDeploy の確認

マネージメントコンソールで、CodeDeploy を選択し、実行中のデプロイメントID をクリックすると、デプロイの様子を観測できます。  
置換が終わったら、ELBEndpoint を再度書くにすると、Ver2.0.0:Green に変わっていることを確認できます。 
デフォルトの動作では、Green に入れ替わった後に1時間待機しているため、CodeDeploy のデプロイ画面にて、"元のタスクセットの修了" ボタンをクリックすると即座にデプロイ処理が完了します。


# 後片付け

手順の逆で、リソースを削除してください。

## ECS の後片付け
1. ECS サービスの削除
2. タスクの削除
3. ECS クラスターの削除
4. タスク定義の削除 (すべてのリビジョンを登録解除)

## CodeDeploy の後片付け
1. CodeDeploy -> アプリケーション から"AppECS-ECSSampleClsuter-ECSSampleService" アプリケーションを削除

## ECR の後片付け
1. ECR 上のecssample を削除

## CloufFormation の後片付け
1. 最初に作成したStack を削除

## Cloud9 の後片付け
1. Cloud9 Environment を削除

以上です。




  - 
    
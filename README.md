## Resolução Desafio - PICK 2024_01
Este repositório contém a minha resolução do [desafio proposto](https://github.com/badtuxx/LINUXtips-PICK-24_01) pelo [@Badtuxx](https://github.com/badtuxx) para a Turma do PICK 2024.
A ideia principal do desafio é realizar a criação de um ambiente Kubernetes gerenciado e totalmente seguro para executar de maneira eficaz a aplicação **Giropops Senhas**
A aplicação **Giropops Senhas** é uma ferramenta desenvolvida pela LinuxTips durante live na Twitch para ajudar os usuários a criar senhas fortes e seguras de forma rápida e personalizada. Ela permite que você gere senhas aleatórias, escolhendo o tamanho das senhas, e se fará a inclusão de caracteres especiais e/ou números.
## Sumário desta Doc:

 - Stack de Ferramentas
 - Criação da Infraestrutura
 - Diferentes formas para se criar uma imagem
 - Criando Deploys com Helm
 - Garantindo a segurança com Kyverno
 - Utilizando o Harbor para garantir imagens seguras
 - Monitorando nossa Aplicação

Para resolver esse desafio, eu utilizei as seguintes ferramentas/ tecnologias:
### Stack de Ferramentas/ Tecnologias:

 - [APKO](https://github.com/chainguard-dev/apko)
 - [Distroless](https://edu.chainguard.dev/chainguard/chainguard-images/getting-started-distroless/)
 - [Docker](https://github.com/docker)
 - [Github Actions](https://github.com/features/actions)
 - [Harbor](https://github.com/goharbor/harbor)
 - [Helm](https://helm.sh/)
 - [KEDA](https://github.com/kedacore/keda)
 - [Kubernetes](https://kubernetes.io/pt-br/)
 - [Kyverno](https://kyverno.io/)
 - [Locust](https://locust.io/)
 - [Melange](https://github.com/chainguard-dev/melange)
 - [Nginx-Ingress](https://github.com/kubernetes/ingress-nginx)
 - [Prometheus Stack (+ Grafana)](https://github.com/prometheus-community/helm-charts)
 - [Terraform](https://www.terraform.io/)

### Criação da Infraestrutura
Eu me baseei em outro projeto que desenvolvi ainda durante o PICK2024 para a criação da infraestrutura da minha aplicação, o [k8s-with-ec2](https://github.com/FabioBartoli/k8s-with-ec2). A ideia deste projeto é criar um cluster kubernetes na AWS para estudos, provisionando e configurando máquinas EC2 pequenas utilizando Módulos Terraform + Github Actions, de maneira que esse cluster seja gratuito utilizando o [free tier](https://aws.amazon.com/free/?all-free-tier.sort-by=item.additionalFields.SortRank&all-free-tier.sort-order=asc&awsf.Free%20Tier%20Types=*all&awsf.Free%20Tier%20Categories=*all) da AWS. O projeto é aberto e você pode fazer um fork e configurar suas próprias credenciais para utilizá-lo :) Mais detalhes estão disponíveis na documentação do próprio projeto.
Mas, para esse desafio, as coisas são um pouco diferentes e, apesar de utilizar o mesmo "esqueleto" do Terraform, tive que fazer várias alterações para que o cluster criado suporte tudo que eu utilizarei, inclusive sendo necessário utilizar máquinas fora do free tier para que atendam aos requisitos mínimos do Kubernetes. 
Eu também adicionei em meu Terraform o provisionamento de um Application LoadBalancer e de registros DNS na minha Hosted Zone para apontarem para este LoadBalancer que estarei criando. Aqui, eu tentei "contornar" a utilização do EKS + Network Load Balancer, 2 recursos que possuem custos e não estão inclusos no free tier, pela utilização de instâncias EC2 gerenciadas pelo Kubeadm com um Application Load Balancer, que possui um período de 750 horas/ mês para utilização no Free Tier.
Em resumo, o cenário que eu quis montar foi para pagar o menos possível, em comparativo:
| Stack "Normal" - EKS + Instâncias + NLB             | Preço            | Stack "Manual", EC2 + ALB     | Preço                                  |
|-----------------------------------------------------|------------------|------------------------------------------------|----------------------------------------|
| EKS                                                 | $0,10/hora        | 4 Instâncias (1 CP + 3 Workers) - t3a.small     | (0,0188) * 4 = $0,0752/hora             |
| NLB                                                 | $0,0225/hora      | Application Load Balancer                       | 750 horas/mês grátis no Free Tier      |
| 4 Instâncias (1 CP + 3 Workers) - t3a.small         | (0,0188) * 4 = $0,0752/hora | |                                            |
| **Total**                                           | **$0,1977/hora**  | **Total**                                               |  **$0,0752/hora**                                       |  


O custo de se utilizar a Stack "Normal", se considerar que eu utilizaria 750 horas/ mês, seria de **$148,27 dólares**, enquanto utilizando a stack onde só estou pagando pelas EC2, será de **$56,40 dólares**, uma economia de **mais de 60%**
Claro que essa utilização de um Cluster "manual" possui diversos problemas e é ideal apenas para ambiente de estudos, para pouparmos a carteira 😊. No "mundo real", utilizo o EKS sem pensar duas vezes.
Voltando para a infraestrutura, o "grande truque" para se utilizar o Application Load Balancer é justamente o Nginx Ingress. Ao invés de criá-lo com o tipo default para cloud "LoadBalancer", eu estou criando nos padrões da utilização Bare Metal, criando um serviço "NodePort" e bindando 2 portas:

 - 30080 da máquina -> 80 do Ingress
 - 30443 da máquina -> 443 do Ingress

Quem vai fazer a mágica acontecer é o LoadBalancer: Eu tenho um listener manda as requisições da porta 80 em redirect para a 443, e as requisições da 443 eu encaminho para meu cluster EC2 usando um TargetGroup, diretamente para a porta 30443. E pra melhorar, como meu Application Load Balancer possui um certificado válido na porta 443, as aplicações que forem expostas pelo Ingress irão automaticamente já ter a confiança do meu certificado. 
No desenho abaixo eu tento explicar um pouco melhor tudo que foi feito:

![Arquitetura-Cluster](./docs/images/Arquitetura-Infra.png)

Para fazer o deploy da minha infra, eu tenho um [Pipeline CI/CD diretamente no meu Github Actions](./.github/workflows/deploy-infra.yml), e tudo que eu preciso para executá-lo são esses 4 valores:

![Keys-AWS](./docs/images/AWS-keys.png)

 - *ACCESS_KEY*: Access Key de um usuário do IAM que tenha permissão na AWS para criar e gerenciar instâncias, load balancers, buckets s3 e rotas no route53
 - *SECRET_KEY*: A secret desse usuário
 - *PRIVATE_KEY* e *PUBLIC_KEY* são literalmente uma key gerada em minha máquina local, codificadas em base64 e salvas como secrets no Github. Essas chaves serão utilizadas pelo Terraform para vincular nas EC2 e depois fechar um túnel SSH para fazer a instalação automática do meu Cluster Kubernetes, além da instalação do Helm no meu Worker, adição dos Repos Helm e afins.
Infra criada, vamos ver um pouco sobre a criação da Imagem
### Diferentes formas para se criar uma Imagem
A criação de um Dockerfile é uma prática bastante comum quando pensamos em colocar nossas aplicações para serem executadas em ambientes com orquestração. Temos diversas maneiras de gerar uma imagem como o próprio [Docker](https://www.docker.com/) que acabei de citar, o [Podman](https://podman.io/), e até mesmo a criação das nossas imagens "do zero". Nesse desafio, eu tenho 3 repositórios com a exata mesma aplicação onde eu irei aplicar técnicas de build da imagem diferente, para que possamos comparar os benefícios de cada uma.
#### Primeiro método: O build convencional
[Nessa pasta](./app/normal-giropops-senhas), você vai encontrar o build mais convencional que costumamos fazer: pega uma imagem base, instalamos o que for necessário, definimos o entrypoint da nossa aplicação e sucesso! É uma forma válida de se fazer um deploy, mas vamos olhar para alguns dados:

![build-normal](./docs/images/build-normal.png)

Então, pegamos uma imagem base do python, fizemos todo o processo que precisávamos para o build e construimos uma bela imagem de 148MB. No fim, temos uma imagem com **23 camadas** com o Debian sendo a imagem base:

![camadas-build](./docs/images/camadas-buildnormal.png)

Perceba que o grande problema aqui é que, caso essa nossa imagem sofra um vazamento ou algo do tipo, qualquer pessoa poderá recuperar qualquer conteúdo que tenha nessas camadas, mesmo que ele tenha sido apagado antes do "build do container final". Além disso, estamos expostos a quaisquer vulnerabilidades que venham a surgir em pacotes nativos do sistema operacional base ou relacionados a alguma ferramenta que um dev venha a incluir nesse nosso Dockerfile. Vamos utilizar o Trivy, uma ferramenta de scan de vulnerabilidades para ver qual o "tamanho do problema" que temos em mãos:

![scan-build](./docs/images/scan-build-normal.png)

Então, temos 105 vulnerabiliadades encontradas, incluindo **1 CRÍTICA**, e dessas 105, apenas 1 possui um fix disponível, fix que com certeza será ou já foi lançado em uma imagem mais recente do python no DockerHub, mas mesmo assim ainda temos bastante coisa. Então, vamos olhar para o segundo cenário

#### Segundo método: Build utilizando Imagens Distroless
Aqui, a ideia é ter imagens que tem apenas os pacotes necessários para rodar nossa aplicação, então, toda a parte dos pacotes do Sistema Operacional e etc que já discutimos antes já não são mais um problema pra gente. Com as imagens Distroless conseguimos ter mais confiabilidade nas nossas imagens criadas. Você pode [verificar aqui](./app/distroless-giropops-senhas/Dockerfile) como utilizei o distroless para criar o Dockerfile do giropops-senhas. Em resumo, utilizamos uma imagem base "builder" com um sistema operacional para fazer todo o processo de build da nossa aplicação e depois copiamos apenas os executáveis necessários para uma imagem do tipo [APKO](https://edu.chainguard.dev/open-source/build-tools/apko/getting-started-with-apko/) usando o conceito de [Docker Multi-Stage](https://docs.docker.com/build/building/multi-stage/)
Agora, vamos verificar como ficou nossa imagem:

![build-distroless](./docs/images/build-distroless.png)

Perceba que o processo de build ficou um pouco mais complexo, mas já temos uma primeira mudança significante: Para a mesma aplicação, conseguimos diminuir para 72MB o tamanho da imagem. Praticamente, cortamos a primeira imagem gerada pela metade
E olhando para as camadas da imagem, também conseguimos perceber que elas reduziram significativamente: agora temos 11 camadas. Todo o processo realizado pelo container "builder" ficou contido dentro de uma única camada base chamada de "apko".

![camadas-distroless](./docs/images/camadas-builddistroless.png)

Outro ponto bem interessante de se notar é que agora eu não consigo mais executar o "cat /etc/os-release" para pegar o meu sistema operacional, pois esse pacote não vem instalado em nossa imagem final. A não presença de pacotes como *cat*, *wget*, *curl* em nossa imagem final é bem interessante quando olhamos para a segurança, visto que diminui a superfície de ataque em nossa imagem. Por fim, vamos verificar as vulnerabilidades pra ver o que temos por aqui..

![scan-distroless](./docs/images/scan-build-distroless.png)

0 vulnerabilidades listadas! Isso mostra o trabalho da Chainguard em manter as imagens atualizadas com os pacotes mais recentes possíveis! Já temos algo bem interessante agora, certo? Mas conseguimos melhorar mais um pouco

#### Terceiro Método: Vamos criar uma imagem do zero?
![Melange](https://64.media.tumblr.com/9d29acae84f6e499a6baffc6ecd2cc9c/tumblr_oyjhay1HcD1qmob6ro1_400.gif)

Aqui, veremos um outra opção muito interessante que a Chainguard nos proporciona: ainda que utilizemos uma imagem base deles, podemos precisar de algo muito específico pra nossa aplicação executar corretamente e iremos acabar instalando em nossa imagem final. O resultado, como já sabemos, são mais camadas e mais possibilidades de termos pacotes que tenham dependências com vulnerabilidades.
Não só para esse cenário do exemplo, mas para qualquer outro, a seguinte alternativa pode ser interessante: que tal construirmos uma imagem do zero com os pacotes que precisamos especificamente para nossa aplicação e somente isso? Logicamente, estamos aumentando mais um pouco o grau de complexidade do nosso build, mas teremos melhores recompensas.
Para fazer esse processo, a Chainguard nos disponibiliza o [Melange](https://github.com/chainguard-dev/melange) ~~(não é a especiaria de Duna, é outro Melange)~~, uma ferramenta que permite criarmos nossa aplicação como um "pacote" junto com suas dependências necessárias e fazer o build disso. Para efeitos de entendimento, nosso processo de criação da imagem fica dividido entre:

 - [Criar o nosso pacote Melange](./security/melange/melange.yaml): Primeiro, vamos buildar nossa aplicação como um pacote com todas as dependências necessárias, e nada mais que isso
 - [Colocar nosso pacote para rodar em uma imagem APKO](./security/melange/apko.yaml): Copiamos nosso aplicação como um pacote para dentro de outra imagem, definimos o seu executável como entrypoint e temos nossa aplicação funcionando maravilhosamente

Dito isto, vou fazer o build da nossa imagem para ver o que acontece: 

![build-melange](./docs/images/build-melange.png)

Podemos ver que a complexidade aumentou mais um pouco, pois agora é gerado um arquivo compactado da nossa aplicação que carregamos para o docker para poder utilizar. Mas já conseguimos diminuir para 59MB (a primeira tinha 148MB), agora sabemos que a imagem tem apenas o que precisamos para executar nossa aplicação. Mas agora, a cereja do bolo:

![camadas-melange](./docs/images/build-melange.png)

Nossa imagem tem APENAS UMA CAMADA apko. O que significa que todo nosso processo de buildar a imagem agora fica abstraído e nenhuma informação sobre isso pode ser descoberto na imagem final. Perceba também que agora o meu comando "docker run" com o "cat /etc/os-release" nem foi respeitado, pois nosso ponto de acesso é justamente a nossa aplicação, sem muitas possibilidades para cair dentro do container. Apenas para não restar dúvidas, vamos rodar o scan nela também:
![scan-melange](./docs/images/scan-build-melange.png)

Também não temos vulnerabilidades. Para o restante deste desafio, eu irei trabalhar com a imagem do giropops-senhas criada via Melange
##

/// 《空之歌》鉴赏模式使用的项目级资源目录。
///
/// 这里有意使用静态目录，而不是在运行时扫描文件系统：发行包、SakiPack 和
/// Flutter AssetBundle 都能得到完全一致的排列顺序；后续接入解锁条件时，也可以
/// 直接在这些条目上补充 unlockId，而不需要改动界面结构。
class AppreciationCharacter {
  const AppreciationCharacter({
    required this.id,
    required this.name,
    required this.poses,
    required this.expressions,
    required this.defaultExpression,
  });

  final String id;
  final String name;
  final List<String> poses;
  final List<String> expressions;
  final String defaultExpression;
}

class AppreciationCg {
  const AppreciationCg.composite({
    required this.title,
    required this.resourceId,
    required this.assetDirectory,
    required this.variants,
  }) : standaloneAsset = null,
       animated = false;

  const AppreciationCg.standalone({
    required this.title,
    required this.standaloneAsset,
    this.animated = false,
  }) : resourceId = null,
       assetDirectory = null,
       variants = const <String>[''];

  final String title;
  final String? resourceId;
  final String? assetDirectory;
  final List<String> variants;
  final String? standaloneAsset;
  final bool animated;

  bool get isComposite => resourceId != null;

  String get baseAsset => 'cg/$assetDirectory/$resourceId-pose1.webp';

  String variantAsset(String variant) =>
      'cg/$assetDirectory/$resourceId-$variant.webp';
}

class AppreciationBackground {
  const AppreciationBackground(this.id, this.title);

  final String id;
  final String title;

  String get assetName => 'backgrounds/$id.webp';
}

class AppreciationMusic {
  const AppreciationMusic(this.id, this.title, this.backgroundId);

  final String id;
  final String title;
  final String backgroundId;

  String get assetPath => 'Assets/music/$id.mp3';

  String get backgroundAsset => 'backgrounds/$backgroundId.webp';
}

const appreciationCharacters = <AppreciationCharacter>[
  AppreciationCharacter(
    id: 'xiayo1',
    name: '夏悠',
    poses: <String>[
      'pose1',
      'pose2',
      'pose3',
      'pose4',
      'pose5',
      'pose6',
      'pose7',
      'pose8',
    ],
    expressions: <String>[
      'akireta',
      'akireta2',
      'akireta3',
      'akireta4',
      'ciallo',
      'dame',
      'dame2',
      'doyagao',
      'happy',
      'hen',
      'kowa',
      'kuraikao',
      'mesugaki',
      'mesugaki2',
      'mesugaki3',
      'moeru',
      'naku',
      'naku2',
      'neko',
      'ochikomu',
      'odoroki',
      'rena',
      'shy1',
      'shy2',
      'shy3',
      'shy4',
      'shy5',
      'smile',
      'smilenaka1',
      'smilenaka2',
      'smilenaka3',
      'star',
      'tabetaibase',
      'tameiki',
      'tameiki2',
      'think',
      'think2',
      'unhappy',
      'wakuwaku',
      'wakuwaku2',
      'wakuwaku3',
      'what',
    ],
    defaultExpression: 'smile',
  ),
  AppreciationCharacter(
    id: 'xiayo2',
    name: '夏悠（第二章）',
    poses: <String>[
      'pose1',
      'pose2',
      'pose3',
      'pose4',
      'pose5',
      'pose6',
      'pose7',
      'pose8',
      'pose9',
      'pose10',
      'pose11',
      'pose12',
      'pose13',
      'pose14',
      'pose15',
    ],
    expressions: <String>[
      'akireta',
      'akireta2',
      'akireta3',
      'akireta4',
      'ciallo',
      'ciallo2',
      'dame',
      'dame2',
      'dame3',
      'doyagao',
      'fusigi',
      'happy',
      'happy2',
      'hen',
      'kirakira',
      'kowa',
      'mesugaki',
      'mesugaki2',
      'mesugaki3',
      'mesugaki4',
      'moeru',
      'naku',
      'naku2',
      'nande',
      'neko',
      'ochikomu',
      'odoroki',
      'odoroki2',
      'rue',
      'shy1',
      'shy2',
      'shy3',
      'shy4',
      'shy5',
      'smile',
      'smile2',
      'smile3',
      'smilenaka',
      'smilenaka0',
      'smilenaka1',
      'smilenaka2',
      'smilenaka3',
      'smilenaka4',
      'star',
      'tabetaibase',
      'tameiki',
      'tameiki2',
      'think',
      'think2',
      'unhappy',
      'wakuwaku',
      'wakuwaku2',
      'wakuwaku3',
      'what',
    ],
    defaultExpression: 'smile',
  ),
  AppreciationCharacter(
    id: 'shioke',
    name: '萧可',
    poses: <String>['pose1', 'pose2', 'pose3', 'pose4'],
    expressions: <String>[
      'unhappy',
      'emm',
      'emm2',
      'happy',
      'happy2',
      'kuraikao',
      'kuraikao2',
      'eye',
      'eye2',
      'eye3',
      'eye4',
      'naku',
      'naku2',
    ],
    defaultExpression: 'happy',
  ),
  AppreciationCharacter(
    id: 'chen',
    name: '陈雏莺',
    poses: <String>['pose1', 'pose2', 'pose3', 'pose4'],
    expressions: <String>[
      'happy',
      'smile',
      'miru',
      'think',
      'tameiki',
      'wakuwaku',
      'doya',
      'odoroki',
      'ikari',
      'ikari2',
      'moeru',
      'moeru2',
      'youki',
    ],
    defaultExpression: 'smile',
  ),
  AppreciationCharacter(
    id: 'syozen1',
    name: '刘守真',
    poses: <String>['pose1', 'pose2'],
    expressions: <String>[
      'eve',
      'happy',
      'kawaii',
      'konoyarou',
      'konoyarou2',
      'kuraikao',
      'magao',
      'mendo',
      'moeru',
      'naruhodo',
      'ochikomu',
      'odoroki',
      'odoroki2',
      'sabishii',
      'sabishii2',
      'think',
      'unhappy',
    ],
    defaultExpression: 'magao',
  ),
  AppreciationCharacter(
    id: 'gonna1',
    name: '李宫娜',
    poses: <String>['pose1', 'pose2', 'pose3'],
    expressions: <String>[
      'angry',
      'angry2',
      'common',
      'happy',
      'hen',
      'hen2',
      'kimoi',
      'kowa',
      'kowa2',
      'nikoniko',
      'nolight',
      'odoroki',
      'oogoe',
      'satoko',
      'satoko2',
      'tameiki',
      'tameiki2',
      'think',
      'think2',
      'think3',
      'warui',
      'what',
      'what2',
    ],
    defaultExpression: 'common',
  ),
];

const appreciationCgs = <AppreciationCg>[
  AppreciationCg.composite(
    title: '草地上的相遇',
    resourceId: 'cgcp0_1',
    assetDirectory: 'cg_cp0_1',
    variants: <String>['1', '2', '3', '4'],
  ),
  AppreciationCg.composite(
    title: '草地谈心',
    resourceId: 'cgcp0_2',
    assetDirectory: 'cg_cp0_1',
    variants: <String>['1', '2', '3', '4', '5', '6'],
  ),
  AppreciationCg.standalone(
    title: '秘密基地的小剧场',
    standaloneAsset: 'cg/cg_cp0_q1.webp',
  ),
  AppreciationCg.composite(
    title: '异议！',
    resourceId: 'cgq2',
    assetDirectory: 'cg_cp0_q2',
    variants: <String>['2', '3', '4', '5', '6', '7', '8', '9'],
  ),
  AppreciationCg.standalone(
    title: '异议！动画',
    standaloneAsset: 'cg/cg_cp0_q2/cg_igiari.webp',
    animated: true,
  ),
  AppreciationCg.standalone(
    title: '突然靠近',
    standaloneAsset: 'cg/cg_cp0_q3.webp',
  ),
  AppreciationCg.composite(
    title: '受伤的夏悠',
    resourceId: 'cg_cp1_1',
    assetDirectory: 'cg_cp1_1',
    variants: <String>['happy', 'naku', 'naku2', 'warui'],
  ),
  AppreciationCg.composite(
    title: '树下',
    resourceId: 'cgtree',
    assetDirectory: 'cg_tree',
    variants: <String>['1', '2', '3'],
  ),
  AppreciationCg.composite(
    title: '守真的回忆',
    resourceId: 'cg_cp1_ls',
    assetDirectory: 'cg_cp1_ls',
    variants: <String>['1', '2'],
  ),
  AppreciationCg.composite(
    title: '追狗大作战',
    resourceId: 'cgdog',
    assetDirectory: 'cg_dog',
    variants: <String>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
      '13',
      '14',
      '15',
      '16',
    ],
  ),
  AppreciationCg.composite(
    title: '黄昏的笑容',
    resourceId: 'cg_cp1_2',
    assetDirectory: 'cg_cp1_2',
    variants: <String>['1', '2', '3', '4'],
  ),
  AppreciationCg.composite(
    title: '夏日约会',
    resourceId: 'cg_cp1_3',
    assetDirectory: 'cg_cp1_3',
    variants: <String>['1', '2', '3', '4', '5', '6'],
  ),
  AppreciationCg.standalone(title: '奔向星空', standaloneAsset: 'cg/cg_cp1_4.webp'),
  AppreciationCg.composite(
    title: '两个人的夜空',
    resourceId: 'cg_cp1_5',
    assetDirectory: 'cg_cp1_5',
    variants: <String>['1', '2'],
  ),
  AppreciationCg.composite(
    title: '池畔戏水',
    resourceId: 'cg_cp2_pond',
    assetDirectory: 'cg_cp2_pond',
    variants: <String>['1', '2', '3', '4'],
  ),
  AppreciationCg.composite(
    title: '摩托车上的三人',
    resourceId: 'cgmoto',
    assetDirectory: 'cgmoto',
    variants: <String>['1', '2'],
  ),
  AppreciationCg.composite(
    title: '第一次看猫',
    resourceId: 'shincg3',
    assetDirectory: 'shincg3',
    variants: <String>['1', '2', '3', '4'],
  ),
  AppreciationCg.composite(
    title: '萧可的漫画梦',
    resourceId: 'shincg4',
    assetDirectory: 'shincg4',
    variants: <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11'],
  ),
  AppreciationCg.composite(
    title: '黄昏读书',
    resourceId: 'shincg5',
    assetDirectory: 'shincg5',
    variants: <String>['1', '2', '3', '4', '5', '6'],
  ),
  AppreciationCg.composite(
    title: '十字路口的白日梦',
    resourceId: 'shincg6',
    assetDirectory: 'shincg6',
    variants: <String>['1'],
  ),
  AppreciationCg.composite(
    title: '萧可家门口',
    resourceId: 'shincg7',
    assetDirectory: 'shincg7',
    variants: <String>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
    ],
  ),
  AppreciationCg.composite(
    title: '夏悠的回眸',
    resourceId: 'shincg9',
    assetDirectory: 'shincg9',
    variants: <String>['1', '2', '3', '4'],
  ),
  AppreciationCg.composite(
    title: '怀中恸哭',
    resourceId: 'shincg9_embrace',
    assetDirectory: 'shincg9_embrace',
    variants: <String>['1'],
  ),
  AppreciationCg.composite(
    title: '穿越后的重逢',
    resourceId: 'shincg10',
    assetDirectory: 'shincg10',
    variants: <String>['2', '3', '4'],
  ),
  AppreciationCg.composite(
    title: '山巅黄昏',
    resourceId: 'shincg11',
    assetDirectory: 'shincg11',
    variants: <String>['1'],
  ),
  AppreciationCg.standalone(title: '蝉', standaloneAsset: 'cg/cgchan.webp'),
];

const appreciationBackgrounds = <AppreciationBackground>[
  AppreciationBackground('bamboo', '竹林'),
  AppreciationBackground('bamboo-yuu', '夕暮竹林'),
  AppreciationBackground('blackboard', '黑板'),
  AppreciationBackground('chapter0', '序章'),
  AppreciationBackground('chapter1', '第一章'),
  AppreciationBackground('classroom', '教室'),
  AppreciationBackground('forest', '树林'),
  AppreciationBackground('grass', '草地'),
  AppreciationBackground('hatake', '田野'),
  AppreciationBackground('home-asa', '清晨的家'),
  AppreciationBackground('home-yuu', '黄昏的家'),
  AppreciationBackground('home-yuu2', '暮色中的家'),
  AppreciationBackground('home-yoru', '夜晚的家'),
  AppreciationBackground('jiko', '事故现场'),
  AppreciationBackground('kichi', '秘密基地'),
  AppreciationBackground('otherroad-asa', '清晨的小路'),
  AppreciationBackground('otherroad-yuu', '黄昏的小路'),
  AppreciationBackground('school', '学校'),
  AppreciationBackground('school-yuu', '黄昏的学校'),
  AppreciationBackground('sky', '晴空'),
  AppreciationBackground('sky-yuu', '夕空'),
  AppreciationBackground('sky-yoru', '夜空'),
  AppreciationBackground('stone-asa', '清晨的石阶'),
  AppreciationBackground('stone-yuu', '黄昏的石阶'),
  AppreciationBackground('stone-yoru', '夜晚的石阶'),
  AppreciationBackground('sun', '阳光'),
  AppreciationBackground('to-school', '上学路'),
  AppreciationBackground('toschool-yuu', '放学路'),
  AppreciationBackground('tosi', '街道'),
  AppreciationBackground('tosi2', '街道二'),
  AppreciationBackground('tosi3', '街道三'),
  AppreciationBackground('tosi4', '街道四'),
];

const appreciationMusic = <AppreciationMusic>[
  // 背景依据原作音乐定义中的意境注释，以及曲目在剧本中的典型场景选择。
  AppreciationMusic('amaiomoide', '甘美的回忆', 'toschool-yuu'),
  AppreciationMusic('asa', '清晨', 'otherroad-asa'),
  AppreciationMusic('asanimukau', '迎向清晨', 'sky'),
  AppreciationMusic('chen', '闲暇时光', 'school'),
  AppreciationMusic('dream', '梦', 'home-asa'),
  AppreciationMusic('ed', '片尾曲', 'sky-yuu'),
  AppreciationMusic('edchen', '陈雏莺篇·片尾曲', 'sky'),
  AppreciationMusic('edshioke', '萧可篇·片尾曲', 'sky-yoru'),
  AppreciationMusic('futari', '两个人', 'classroom'),
  AppreciationMusic('game', '游戏时间', 'kichi'),
  AppreciationMusic('gogo', '前进！', 'grass'),
  AppreciationMusic('goodday', '美好的一天', 'to-school'),
  AppreciationMusic('hadaka', '赤裸的心', 'home-yuu2'),
  AppreciationMusic('hatake', '田野', 'hatake'),
  AppreciationMusic('heroine', '女主角', 'stone-asa'),
  AppreciationMusic('himitsukichi', '秘密基地', 'kichi'),
  AppreciationMusic('itami', '痛楚', 'jiko'),
  AppreciationMusic('jyugyo', '课堂', 'classroom'),
  AppreciationMusic('kaiwa', '对话', 'classroom'),
  AppreciationMusic('keikaku', '计划', 'forest'),
  AppreciationMusic('kekkon', '婚礼', 'sun'),
  AppreciationMusic('nandato', '你说什么？', 'blackboard'),
  AppreciationMusic('omoi', '思念', 'sky-yuu'),
  AppreciationMusic('omoide', '回忆', 'forest'),
  AppreciationMusic('op', '主题曲', 'sky'),
  AppreciationMusic('perusona', 'Persona', 'tosi4'),
  AppreciationMusic('play', '玩耍', 'school'),
  AppreciationMusic('school', '校园', 'blackboard'),
  AppreciationMusic('sizukanaasa', '寂静的清晨', 'sky'),
  AppreciationMusic('sky', '天空', 'bamboo'),
  AppreciationMusic('skysoul', '天空之魂', 'sky'),
  AppreciationMusic('sukuu', '拯救', 'forest'),
  AppreciationMusic('think', '思考', 'sky-yuu'),
  AppreciationMusic('what', '怎么回事？', 'kichi'),
  AppreciationMusic('yasumijikan', '课间', 'school'),
  AppreciationMusic('yomi', '黄泉', 'sky-yoru'),
  AppreciationMusic('yoru', '夜', 'home-yoru'),
  AppreciationMusic('yozora', '夜空', 'stone-yoru'),
  AppreciationMusic('yuugure', '黄昏', 'otherroad-yuu'),
];

String appreciationPoseLabel(String pose) {
  final match = RegExp(r'(\d+)$').firstMatch(pose);
  return '姿势 ${match?.group(1) ?? pose}';
}

String appreciationExpressionLabel(String expression) {
  const exactLabels = <String, String>{'satoko': '调侃', 'satoko2': '盘算'};
  final exactLabel = exactLabels[expression];
  if (exactLabel != null) {
    return exactLabel;
  }

  final match = RegExp(r'^(.*?)(\d+)?$').firstMatch(expression);
  final base = match?.group(1) ?? expression;
  final variant = match?.group(2);
  const labels = <String, String>{
    'akireta': '无语',
    'angry': '生气',
    'ciallo': '道歉',
    'common': '平常',
    'dame': '不行',
    'doya': '得意',
    'doyagao': '得意',
    'emm': '皱眉',
    'eye': '眯眼',
    'eve': '认真',
    'fusigi': '疑惑',
    'happy': '开心',
    'hen': '疑惑',
    'ikari': '生气',
    'kawaii': '可爱',
    'kimoi': '嫌弃',
    'kirakira': '闪闪发亮',
    'konoyarou': '恼火',
    'kowa': '害怕',
    'kuraikao': '阴沉',
    'magao': '正经',
    'mendo': '嫌麻烦',
    'mesugaki': '小恶魔',
    'miru': '观察',
    'moeru': '热血',
    'naku': '哭泣',
    'nande': '怎么会',
    'naruhodo': '原来如此',
    'neko': '猫猫',
    'nikoniko': '笑眯眯',
    'nolight': '无神',
    'ochikomu': '沮丧',
    'odoroki': '惊讶',
    'oogoe': '大喊',
    'rena': '礼奈',
    'rue': '闹别扭',
    'sabishii': '寂寞',
    'shy': '害羞',
    'smile': '微笑',
    'smilenaka': '含泪微笑',
    'star': '星星眼',
    'tabetaibase': '想吃',
    'tameiki': '叹气',
    'think': '思考',
    'unhappy': '不高兴',
    'wakuwaku': '期待',
    'warui': '坏笑',
    'what': '困惑',
    'youki': '狂气',
  };
  final label = labels[base] ?? expression;
  return variant == null ? label : '$label $variant';
}

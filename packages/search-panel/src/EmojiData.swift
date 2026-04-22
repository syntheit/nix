import Foundation

struct EmojiResult {
    let character: String
    let name: String
}

enum EmojiStore {
    private static let all: [(character: String, name: String, keywords: [String])] = {
        rawData.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3 else { return nil }
            let char = String(parts[0])
            let name = String(parts[1])
            let keywords = parts[2].split(separator: ",").map { String($0).lowercased() }
                + name.lowercased().split(separator: " ").map(String.init)
            return (char, name, keywords)
        }
    }()

    static func search(_ query: String) -> [EmojiResult] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }

        return all.filter { emoji in
            emoji.keywords.contains { $0.hasPrefix(q) }
        }.sorted { a, b in
            let aExact = a.keywords.contains { $0 == q }
            let bExact = b.keywords.contains { $0 == q }
            if aExact != bExact { return aExact }
            return a.name < b.name
        }.map { EmojiResult(character: $0.character, name: $0.name) }
    }

    // Format: emoji|Display Name|keyword1,keyword2,...
    private static let rawData = """
    😀|Grinning Face|grin,happy,smile
    😃|Smiley|smiley,happy,grin
    😄|Smile|smile,happy,grin
    😁|Beaming Face|beaming,grin
    😆|Laughing|laughing,lol,haha
    😂|Tears of Joy|joy,lol,laugh,tears,funny,crying
    🤣|ROFL|rofl,lol,rolling
    😊|Blush|blush,happy
    😇|Angel|angel,innocent,halo
    🥰|Love Face|love,hearts,adore
    😍|Heart Eyes|heart,eyes,love,crush
    🤩|Star Struck|star,struck,excited,amazing
    😘|Kissing Heart|kiss,love,smooch
    😋|Yummy|yummy,delicious,tongue
    😛|Tongue|tongue,playful
    😜|Wink Tongue|wink,tongue,crazy
    🤪|Zany|zany,crazy,wild
    🤑|Money Face|money,rich,dollar
    🤗|Hug|hug,hugging
    🤭|Giggle|giggle,oops,tee-hee
    🤫|Shush|shush,quiet,secret
    🤔|Thinking|thinking,hmm,consider
    🤐|Zipper Mouth|zipper,secret,quiet
    🤨|Raised Eyebrow|eyebrow,skeptical,sus
    😐|Neutral|neutral,meh,blank
    😑|Expressionless|expressionless,meh
    😶|No Mouth|silent,speechless
    😏|Smirk|smirk,suggestive,sly
    😒|Unamused|unamused,annoyed
    🙄|Eye Roll|eyeroll,annoyed,whatever
    😬|Grimace|grimace,awkward,nervous
    😮‍💨|Exhale|exhale,sigh,relief
    🤥|Liar|liar,pinocchio,lying
    😌|Relieved|relieved,peaceful,calm
    😔|Pensive|pensive,sad,thoughtful
    😪|Sleepy|sleepy,tired
    🤤|Drooling|drooling,delicious
    😴|Sleeping|sleeping,zzz,tired
    😷|Mask|mask,sick,covid
    🤒|Sick|sick,thermometer,fever
    🤕|Bandage|hurt,injured
    🤢|Nauseous|nauseous,sick,green
    🤮|Vomit|vomit,sick,puke
    🥵|Hot Face|hot,sweating,heat
    🥶|Cold Face|cold,freezing,ice
    🥴|Woozy|woozy,dizzy,drunk
    🤯|Mind Blown|mind,blown,explode,shocked
    🤠|Cowboy|cowboy,yeehaw,western
    🥳|Party Face|party,celebrate,birthday
    🥸|Disguise|disguise,glasses,nose
    😎|Sunglasses|cool,sunglasses,chill
    🤓|Nerd|nerd,glasses,geek
    😕|Confused|confused,puzzled
    😟|Worried|worried,concerned
    🙁|Frown|frown,sad
    😮|Surprised|surprised,wow
    😲|Astonished|astonished,shocked
    😳|Flushed|flushed,embarrassed
    🥺|Pleading|pleading,puppy,please
    😨|Fearful|fearful,scared,afraid
    😰|Anxious|anxious,nervous,sweat
    😢|Crying|crying,tear,sad
    😭|Sobbing|sobbing,crying,tears,sad,bawling
    😱|Scream|scream,scared,horror,omg
    😖|Confounded|confounded,frustrated
    😩|Weary|weary,tired,frustrated
    😤|Triumph|triumph,angry,huff
    😡|Angry|angry,mad,rage
    😠|Mad|mad,angry
    🤬|Swearing|swearing,censored,angry,expletive
    😈|Devil|devil,evil,mischief,horns
    👿|Angry Devil|devil,angry,evil
    💀|Skull|skull,dead,death,rip
    💩|Poop|poop,poo,shit
    🤡|Clown|clown
    👻|Ghost|ghost,boo,halloween
    👽|Alien|alien,ufo
    👾|Space Invader|invader,alien,game
    🤖|Robot|robot,bot
    👋|Wave|wave,hi,hello,bye
    🤚|Raised Hand|hand,stop
    🖐️|Splayed Hand|hand,five
    ✋|High Five|high-five,stop
    🖖|Vulcan|vulcan,spock
    👌|OK Hand|ok,perfect,fine
    🤌|Pinched Fingers|pinched,italian,chef
    🤏|Pinching|pinching,small,tiny
    ✌️|Peace|peace,victory,two
    🤞|Crossed Fingers|crossed,fingers,luck,hope
    🫶|Heart Hands|heart,hands,love
    🤟|Love You|love,ily
    🤘|Rock|rock,metal,horns
    🤙|Call Me|call,shaka,hang-loose
    👈|Point Left|point,left
    👉|Point Right|point,right
    👆|Point Up|point,up
    👇|Point Down|point,down
    👍|Thumbs Up|thumbsup,yes,good,like,approve
    👎|Thumbs Down|thumbsdown,no,bad,dislike
    ✊|Fist|fist,punch
    👊|Fist Bump|bump,punch
    👏|Clap|clap,applause,bravo
    🙌|Raised Hands|raise,hooray,celebrate
    👐|Open Hands|open,jazz
    🤝|Handshake|handshake,deal,agreement
    🙏|Pray|pray,please,namaste,thanks,hope,folded
    💅|Nail Polish|nail,polish,sassy,fabulous
    💪|Flexed Biceps|flex,strong,muscle,bicep,power
    🦾|Mechanical Arm|mechanical,robot,prosthetic
    🧠|Brain|brain,smart,think,mind
    👀|Eyes|eyes,look,see,watch
    👁️|Eye|eye,look,see
    👅|Tongue|tongue,lick,taste
    👄|Mouth|mouth,lips,kiss
    🫡|Salute|salute,respect
    🫠|Melting|melting,hot,disappear
    🫣|Peeking|peeking,shy
    🫢|Hand Over Mouth|oops,surprised
    ❤️|Red Heart|heart,red,love
    🧡|Orange Heart|heart,orange
    💛|Yellow Heart|heart,yellow
    💚|Green Heart|heart,green
    💙|Blue Heart|heart,blue
    💜|Purple Heart|heart,purple
    🖤|Black Heart|heart,black,dark
    🤍|White Heart|heart,white
    💔|Broken Heart|broken,heartbreak,sad
    ❤️‍🔥|Heart on Fire|heart,fire,passion
    ❤️‍🩹|Mending Heart|heart,mending,healing
    💕|Two Hearts|hearts,love
    💞|Revolving Hearts|hearts,revolving,love
    💓|Beating Heart|heart,beating
    💗|Growing Heart|heart,growing
    💖|Sparkling Heart|heart,sparkling
    💘|Heart Arrow|heart,arrow,cupid
    💯|Hundred|hundred,100,perfect,score
    💢|Anger|anger,angry
    💥|Boom|boom,explosion,crash,collision
    💦|Sweat Drops|sweat,water,splash
    💨|Dash|dash,wind,fast
    🔥|Fire|fire,hot,lit,flame
    ✨|Sparkles|sparkles,shine,stars,clean,magic
    ⭐|Star|star,favorite
    🌟|Glowing Star|star,glow,bright
    💫|Dizzy Star|star,dizzy,shooting
    🎉|Party Popper|party,celebrate,tada,hooray
    🎊|Confetti|confetti,celebrate,party
    🎈|Balloon|balloon,party,birthday
    🎁|Gift|gift,present,wrapped
    🏆|Trophy|trophy,winner,champion,award
    🥇|Gold Medal|gold,medal,first,winner
    🥈|Silver Medal|silver,medal,second
    🥉|Bronze Medal|bronze,medal,third
    ⚽|Soccer|soccer,football
    🏀|Basketball|basketball
    🏈|Football|football,american
    🎮|Controller|game,controller,gaming,video
    🎲|Dice|die,dice,game,random
    🎵|Music Note|music,note,song
    🎶|Music Notes|music,notes,song,melody
    🎤|Microphone|microphone,karaoke,singing
    🎧|Headphones|headphones,music,audio
    📱|Phone|phone,mobile,cell,iphone
    💻|Laptop|laptop,computer,mac
    ⌨️|Keyboard|keyboard,type
    🖥️|Desktop|desktop,computer,monitor
    📷|Camera|camera,photo
    🔍|Search|search,magnifying,glass,find
    🔑|Key|key,lock,password
    🔒|Lock|lock,secure,private
    🔓|Unlock|unlock,open
    💡|Light Bulb|light,bulb,idea
    🔔|Bell|bell,notification,alert
    📣|Megaphone|megaphone,announcement
    📌|Pin|pin,pushpin,location
    📎|Paperclip|paperclip,attachment
    ✂️|Scissors|scissors,cut
    📝|Memo|memo,note,write
    📚|Books|books,library,read,study
    📧|Email|email,mail,envelope
    📦|Package|package,box,delivery
    🗑️|Trash|trash,delete,garbage,bin
    💰|Money Bag|money,bag,rich,dollar
    💵|Dollar|dollar,money,cash,bill
    💳|Credit Card|credit,card,payment
    📊|Chart|chart,graph,stats,data
    📈|Chart Up|chart,up,trending,growth
    📉|Chart Down|chart,down,decline
    ⏰|Alarm|alarm,clock,time,wake
    ⏳|Hourglass|hourglass,time,wait,timer
    🔧|Wrench|wrench,tool,fix,settings
    🔨|Hammer|hammer,tool,build
    ⚙️|Gear|gear,settings,cog
    💎|Gem|gem,diamond,jewel
    🚀|Rocket|rocket,launch,space,fast,ship
    ✈️|Airplane|airplane,travel,fly,flight
    🚗|Car|car,drive,vehicle
    🏠|House|house,home
    🏢|Office|office,building,work
    🌍|Globe|globe,earth,world,planet
    🌙|Moon|moon,night,crescent
    ☀️|Sun|sun,sunny,bright
    🌈|Rainbow|rainbow,pride,colors
    ☁️|Cloud|cloud,weather
    ❄️|Snowflake|snow,snowflake,cold,winter
    🌊|Ocean Wave|wave,ocean,water,sea,surf
    🌸|Cherry Blossom|cherry,blossom,flower,spring
    🌹|Rose|rose,flower
    🌻|Sunflower|sunflower,flower
    🍀|Four Leaf Clover|clover,luck,lucky
    🌲|Pine Tree|pine,tree,evergreen
    🌴|Palm Tree|palm,tree,tropical,beach
    🐶|Dog|dog,puppy,pet,woof
    🐱|Cat|cat,kitten,pet,meow
    🐭|Mouse|mouse,rodent
    🐰|Rabbit|rabbit,bunny
    🦊|Fox|fox,foxy
    🐻|Bear|bear,teddy
    🐼|Panda|panda
    🐨|Koala|koala
    🐯|Tiger|tiger
    🦁|Lion|lion,king
    🐷|Pig|pig,oink
    🐸|Frog|frog,toad
    🐵|Monkey|monkey,ape
    🐧|Penguin|penguin,bird
    🦅|Eagle|eagle,bird,freedom
    🦆|Duck|duck,bird,quack
    🦉|Owl|owl,bird,wise
    🐝|Bee|bee,honey,buzz
    🦋|Butterfly|butterfly,pretty
    🐍|Snake|snake,reptile
    🐢|Turtle|turtle,slow
    🐙|Octopus|octopus
    🦈|Shark|shark,ocean,jaws
    🦕|Dinosaur|dinosaur,dino
    🦖|T-Rex|trex,dinosaur,dino
    🍕|Pizza|pizza,food,slice
    🍔|Burger|burger,hamburger,food
    🌮|Taco|taco,mexican,food
    🌯|Burrito|burrito,wrap,food
    🍟|Fries|fries,french,food
    🍿|Popcorn|popcorn,movie,snack
    🍩|Donut|donut,doughnut,sweet
    🍪|Cookie|cookie,sweet,biscuit
    🎂|Birthday Cake|cake,birthday,dessert
    🍰|Cake Slice|cake,slice,dessert,pie
    🍫|Chocolate|chocolate,candy,sweet
    🍺|Beer|beer,drink,alcohol
    🍻|Cheers|cheers,beer,toast
    🥂|Champagne|champagne,toast,celebrate
    🍷|Wine|wine,drink,glass
    🍸|Cocktail|cocktail,drink,martini
    ☕|Coffee|coffee,tea,drink,cafe
    🧋|Bubble Tea|bubble,tea,boba
    🍜|Noodles|noodles,ramen,soup
    🍣|Sushi|sushi,japanese,fish
    🥗|Salad|salad,healthy,green
    🍳|Egg|egg,cooking,breakfast
    🥑|Avocado|avocado,guac
    🍌|Banana|banana,fruit
    🍎|Apple|apple,fruit
    🍊|Orange|orange,fruit,citrus
    🍓|Strawberry|strawberry,berry
    🍉|Watermelon|watermelon,fruit,summer
    🌶️|Hot Pepper|pepper,hot,spicy,chili
    🇺🇸|USA|usa,us,america,flag
    🇬🇧|UK|uk,gb,britain,flag
    🇧🇷|Brazil|brazil,br,flag
    🇦🇷|Argentina|argentina,ar,flag
    🇲🇽|Mexico|mexico,mx,flag
    🇨🇦|Canada|canada,ca,flag
    🇯🇵|Japan|japan,jp,flag
    🇩🇪|Germany|germany,de,flag
    🇫🇷|France|france,fr,flag
    🇪🇸|Spain|spain,es,flag
    🇮🇹|Italy|italy,it,flag
    🇧🇴|Bolivia|bolivia,bo,flag
    🇨🇴|Colombia|colombia,co,flag
    🇵🇪|Peru|peru,pe,flag
    🇻🇪|Venezuela|venezuela,ve,flag
    🇨🇱|Chile|chile,cl,flag
    🏳️‍🌈|Rainbow Flag|rainbow,pride,lgbtq,flag
    🏴‍☠️|Pirate Flag|pirate,skull,flag
    ✅|Check Mark|check,done,yes,correct,complete
    ❌|Cross Mark|cross,no,wrong,error,cancel,x
    ⚠️|Warning|warning,caution,alert
    🚫|Prohibited|prohibited,forbidden,no,ban
    💤|Zzz|zzz,sleep,tired
    💬|Speech Bubble|speech,bubble,chat,message,talk
    💭|Thought Bubble|thought,bubble,thinking
    🔴|Red Circle|red,circle,stop
    🟢|Green Circle|green,circle,go
    🔵|Blue Circle|blue,circle
    🟡|Yellow Circle|yellow,circle
    🟣|Purple Circle|purple,circle
    ⬛|Black Square|black,square
    ⬜|White Square|white,square
    🔶|Orange Diamond|diamond,orange
    🔷|Blue Diamond|diamond,blue
    ➡️|Right Arrow|arrow,right,next
    ⬅️|Left Arrow|arrow,left,back
    ⬆️|Up Arrow|arrow,up
    ⬇️|Down Arrow|arrow,down
    🔄|Refresh|refresh,reload,cycle,arrows
    ➕|Plus|plus,add,new
    ➖|Minus|minus,subtract,remove
    ♻️|Recycle|recycle,green,environment
    🚩|Red Flag|redflag,warning
    """
}

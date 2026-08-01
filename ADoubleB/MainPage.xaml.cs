using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;

namespace ADoubleB
{
    public partial class MainPage : ContentPage
    {
        public ObservableCollection<string> UserHistory { get; set; } = new ObservableCollection<string>();//使用者的歷史遊玩紀錄
        bool IsFirstTime = true;//判斷是否為第一次進入遊戲
        int aCount, bCount,tryCount;
        int SystemNumber;


        public MainPage()
        {
            InitializeComponent();
            BindingContext = this;
            SystemNumber= CreateRandomNumber();
        }

        private async void OnPlayClicked(object? sender, EventArgs e)
        {
            if (IsFirstTime)
            {
                PlayLabel.Text = "請輸入你的數字";
                NumberEntry.IsVisible = true;
                PlayButton.Text = "點我查看結果";
                IsFirstTime = false;
                return;
            }
            Debug.WriteLine($"系統產生的數字為：{SystemNumber}");
            
            bool IsUserEntryVaile = await CheckIsUserEntryVaild();
            if (!IsUserEntryVaile) return;
            int userNumber = ParseUserNumber();
            tryCount++;
            await CheckUserNumber(userNumber, SystemNumber);
        }
        private void OnRestartClicked(object? sender, EventArgs e)
        {
            ClearHistory();
            RestartButton.IsVisible = false;
            PlayButton.IsVisible = true;
        }
        /// <summary>
        /// 確認使用者輸入合法數字(數字不得為空、不得重複、必須是四位數數字等)
        /// </summary>
        /// <returns>回傳使用者輸入是否合法</returns>
        private async Task<bool> CheckIsUserEntryVaild()
        {
            HashSet<char> numHS=new HashSet<char>();
            var entryStr=NumberEntry.Text;
            if (string.IsNullOrEmpty(entryStr) ||string.IsNullOrWhiteSpace(entryStr))
            {
                await DisplayAlertAsync("提示", "請輸入數字", "ok");
                return false;
            }
            if(!int.TryParse(entryStr,out int num))
            {
                await DisplayAlertAsync("提示", "請勿輸入特殊符號", "ok");
                return false;
            }
            var len=NumberEntry.Text.Length;
            if (len != 4)
            {
                await DisplayAlertAsync("提示", "請輸入4位數的數字", "ok");
                return false;
            }

            foreach(var str in entryStr)
            {
                numHS.Add(str);
            }
            if(numHS.Count != 4)
            {
                await DisplayAlertAsync("提示", "請勿輸入重複的數字", "ok");
                return false;
            }
            return true;
        }
        private int ParseUserNumber()
        {
            return int.Parse(NumberEntry.Text);
        }
        /// <summary>
        /// 自動產生數字
        /// </summary>
        /// <returns></returns>
        private int CreateRandomNumber()
        {
            string numStr = "";
            List<int>numList=new List<int>
            {
                0,1,2,3,4,5,6,7,8,9
            };
            var random=new Random();
            for(int i = 0; i < 4; i++)
            {
                var num = numList[random.Next(0, numList.Count)];
                numList.Remove(num);
                numStr += num.ToString();
            }
            Debug.WriteLine($"產生的數字：{Convert.ToInt32(numStr)}");
            return Convert.ToInt32(numStr);
          
        }
        private async Task CheckUserNumber(int userNumber,int systemNumber)
        {
            //先將數字歸0
            aCount = 0;
            bCount = 0;
            //A的定義：數字跟位置都相同；B的定義：數字存在但在不同位置
            var userNumStr = userNumber.ToString();
            var systemNumStr = systemNumber.ToString();
            for (int i = 0; i < systemNumStr.Length; i++) 
            {
                for(int j=0;j<userNumStr.Length;j++)
                {
                    if (Convert.ToInt32(systemNumStr[i]) == Convert.ToInt32(userNumStr[j]))//數字存在但不確定是否一樣
                    {
                        if (i == j)//確定位置一樣(索引相同)
                        {
                            aCount++;
                        }
                        else
                        {
                            bCount++;
                        }
                    }
                }
            }
            var message = $"輸入數字：{userNumber}，{aCount}a{bCount}b，第{tryCount}次嘗試";
            UserHistory.Add(message);
            Debug.WriteLine($"歷史筆數：{UserHistory.Count}");
            await DisplayAlertAsync("遊玩提示",$"{message}","確認");
            Debug.WriteLine($"{message}");
            if (aCount == 4)
            {
                await DisplayAlertAsync("遊玩提示", $"恭喜你答對了，共花了{tryCount}次", "確認");
                SystemNumber = CreateRandomNumber();//重新產生數字
                RestartButton.IsVisible = true;
                PlayButton.IsVisible = false;
                return;
                
                
            }
        }
        private void ClearHistory()
        {
            UserHistory.Clear();
            tryCount = 0;
            NumberEntry.Text = string.Empty;
        }
       
    }
}

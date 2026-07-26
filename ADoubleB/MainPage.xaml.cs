using static System.Net.Mime.MediaTypeNames;

namespace ADoubleB
{
    public partial class MainPage : ContentPage
    {
        bool IsFirstTime = true;
        
        

        public MainPage()
        {
            InitializeComponent();
        }

        private async void OnPlayClicked(object? sender, EventArgs e)
        {
            if (IsFirstTime)
            {
                NumberEntry.IsVisible = true;
                PlayButton.Text = "點我查看結果";
                IsFirstTime = false;
                return;
            }
            int TrueNumber = CreateRandomNumber();
            bool IsUserEntryVaile = await CheckIsUserEntryVaild();
            if (!IsUserEntryVaile) return;
            int userNumber = ParseUserNumber();
            
                await DisplayAlertAsync("提示", "先做到這裡好了", "ok");
              


        }
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
            return Convert.ToInt32(numStr);
          
        }
    }
}

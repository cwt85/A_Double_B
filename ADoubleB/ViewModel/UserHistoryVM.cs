using System.Collections.ObjectModel;

namespace ADoubleB.ViewModel;

public class UserHistoryVM : ContentPage
{
    public static ObservableCollection<UserHistory> UserHistory { get; set; } = new ObservableCollection<UserHistory>();//使用者的歷史遊玩紀錄
    
}
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { Toaster } from "react-hot-toast";

import Login from "./page/login/Login";
import DashboardLayout from "./layouts/DashboardLayout";
import DashboardHome from "./page/dashboard/DashboardHome";
import UserManagement from "./components/UserManagement";
import BookingManagement from "./page/booking/BookingManagement";
import Profile from "./page/profile/Profile";
import ReportsManagement from "./page/reports/ReportsManagement";
import ServiceCategories from "./page/categories/ServiceCategories";




export default function App() {
  return (
    <BrowserRouter>
      <Toaster position="top-right" />

      <Routes>
        {/* Login */}
        <Route path="/" element={<Login />} />

        {/* Dashboard */}
        <Route path="/dashboard" element={<DashboardLayout />}>
          <Route index element={<DashboardHome />} />

        {/* Booking Management */}
        <Route path="bookings" element={<BookingManagement />} />

        {/* User Management */}
        <Route path="users" element={<UserManagement />} />

        {/* Admin Profile Management */}
        <Route path="profile" element={<Profile />} />
        
        {/* Report Management */}
        <Route path="reports" element={<ReportsManagement />} />

        {/* Report Management */}
        <Route path="categories" element={<ServiceCategories />} />


        </Route>

      </Routes>
    </BrowserRouter>
  );
}